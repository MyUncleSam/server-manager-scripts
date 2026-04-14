#!/bin/bash
#
# Podman Module
# Install and manage Podman (daemonless/rootless containers), with support for
# compose and Quadlet deployments, auto-update timer, registries config, and
# companion tools (buildah, skopeo, podman-docker, cockpit-podman).
#

# Get the directory where this script is located
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$MODULE_DIR/.." && pwd)"

# Path to module files directory
MODULE_FILES_DIR="$PROJECT_ROOT/modules-files/podman"
PODMAN_COMPOSE_TEMPLATES="$MODULE_FILES_DIR/compose"
PODMAN_QUADLET_TEMPLATES="$MODULE_FILES_DIR/quadlets"

# Podman stacks directory (rootful compose deployments)
PODMAN_STACKS_DIR="/opt/podman"

# Registries config file
PODMAN_REGISTRIES_CONF="/etc/containers/registries.conf"

# Module metadata
module_info() {
    echo "Podman|Install and manage Podman (daemonless/rootless containers)"
}

#=============================================================================
# Helpers
#=============================================================================

check_podman_installed() {
    command_exists podman
}

get_podman_version() {
    podman --version 2>/dev/null | awk '{print $3}'
}

# Run a command as a regular user, with XDG_RUNTIME_DIR set for user systemd
run_as_user() {
    local user="$1"
    shift
    local uid
    uid=$(id -u "$user") || return 1
    sudo -u "$user" \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        "$@"
}

# Detect compose implementation.
#   "wrapper" = `podman compose` subcommand works (an external provider
#               like docker-compose or podman-compose is on PATH)
#   "python"  = only standalone `podman-compose` (python) is available
#   ""        = no compose tooling installed
# Note: `podman compose` is NOT a native implementation — it dispatches to
# an external provider. podman-compose (the python package) is the most
# common provider on Ubuntu.
detect_compose_impl() {
    if podman compose version &>/dev/null; then
        echo "wrapper"
    elif command_exists podman-compose; then
        echo "python"
    else
        echo ""
    fi
}

#=============================================================================
# Status
#=============================================================================

podman_status() {
    if ! check_podman_installed; then
        ui_msgbox "Podman Status" "Podman is not installed"
        return
    fi

    local info=""
    info+="=== Podman Status ===\n\n"
    info+="Version:      $(get_podman_version)\n"

    # Rootful socket
    local rootful="Stopped"
    if service_is_running podman.socket; then
        rootful="Running (enabled: $(systemctl is-enabled podman.socket 2>/dev/null))"
    fi
    info+="Rootful sock: $rootful\n"

    # Auto-update timer
    local autoupdate="Disabled"
    if systemctl is-active --quiet podman-auto-update.timer; then
        autoupdate="Active"
    fi
    info+="Auto-update:  $autoupdate\n"

    # Compose implementation
    local compose_impl
    compose_impl=$(detect_compose_impl)
    case "$compose_impl" in
        wrapper) info+="Compose:      podman compose (wrapper; external provider found)\n" ;;
        python)  info+="Compose:      podman-compose (python)\n" ;;
        *)       info+="Compose:      not installed (install podman-compose)\n" ;;
    esac

    # Companion tools
    info+="\n=== Companions ===\n"
    for tool in buildah skopeo podman-docker cockpit-bridge; do
        local shown="$tool"
        [[ "$tool" == "cockpit-bridge" ]] && shown="cockpit"
        if package_installed "$tool" || command_exists "$tool"; then
            info+="  [x] $shown\n"
        else
            info+="  [ ] $shown\n"
        fi
    done

    # Rootful container/image counts
    if is_root && check_podman_installed; then
        local containers images
        containers=$(podman ps -a --format '{{.Names}}' 2>/dev/null | wc -l)
        images=$(podman images --format '{{.Repository}}' 2>/dev/null | wc -l)
        info+="\n=== Rootful ===\n"
        info+="Containers:   $containers\n"
        info+="Images:       $images\n"
    fi

    # Users with lingering enabled (rootless candidates)
    info+="\n=== Rootless Users (linger enabled) ===\n"
    local linger_users=""
    if [[ -d /var/lib/systemd/linger ]]; then
        linger_users=$(ls /var/lib/systemd/linger 2>/dev/null | tr '\n' ' ')
    fi
    info+="  ${linger_users:-none}\n"

    local tmpfile
    tmpfile=$(mktemp) || return 1
    echo -e "$info" > "$tmpfile"
    ui_textbox "Podman Status" "$tmpfile"
    rm -f "$tmpfile"
}

#=============================================================================
# Install / Uninstall
#=============================================================================

install_podman() {
    if ! require_root; then
        return 1
    fi

    if check_podman_installed; then
        local version
        version=$(get_podman_version)
        if ! ui_yesno "Podman Installed" "Podman $version is already installed.\n\nReinstall / install additional components?"; then
            return
        fi
    fi

    if ! has_internet; then
        ui_msgbox "Error" "No internet connection.\nPlease check your network and try again."
        return 1
    fi

    # Pick companion components
    local -a checklist=(
        "podman-compose" "Docker Compose compatible CLI (python)" "on"
        "buildah"        "Daemonless OCI image builder" "on"
        "skopeo"         "Copy/inspect images between registries" "on"
        "podman-docker"  "Install docker CLI shim (WARNING: conflicts with docker module)" "off"
        "cockpit-podman" "Web UI for podman via Cockpit" "off"
    )

    local selected
    selected=$(ui_checklist "Podman Components" \
        "Select components to install alongside podman:" \
        "${checklist[@]}") || return 0

    # Warn if installing podman-docker while docker is already installed
    if [[ "$selected" == *"podman-docker"* ]] && command_exists docker; then
        if ! ui_yesno "Conflict warning" \
            "Docker appears to be installed (/usr/bin/docker).\n\n\
The podman-docker package installs a 'docker' shim that replaces the docker binary.\n\
This will conflict with the docker module.\n\n\
Continue installing podman-docker anyway?"; then
            # strip podman-docker from selection
            selected=$(echo "$selected" | tr ' ' '\n' | grep -vE '^"?podman-docker"?$' | tr '\n' ' ')
        fi
    fi

    # Build package list — podman + rootless prerequisites always
    local -a packages=(podman uidmap slirp4netns fuse-overlayfs containers-storage)
    for sel in $selected; do
        sel=$(echo "$sel" | tr -d '"')
        packages+=("$sel")
    done

    # Install
    install_packages "${packages[@]}"

    if ! check_podman_installed; then
        log_error "Podman installation failed"
        ui_msgbox "Error" "Podman installation failed.\nCheck the logs for details."
        return 1
    fi

    local version
    version=$(get_podman_version)
    log_info "Podman $version installed"

    # Enable rootful socket?
    if ui_yesno "Rootful socket (system-wide)" \
        "Enable the system-wide podman.socket?\n\n\
WHAT IT DOES:\n\
  Exposes a Docker-compatible REST API at /run/podman/podman.sock (root-owned).\n\
  Tools like Portainer, Dockge, or docker-compose pointed at DOCKER_HOST can use it.\n\n\
WHEN TO ENABLE:\n\
  • You want to run containers as root, like a classic Docker setup.\n\
  • You need a system-wide socket for management UIs.\n\n\
WHEN TO LEAVE DISABLED:\n\
  • You only want rootless containers (each user gets their own user socket instead).\n\n\
You can toggle this later under 'service'."; then
        systemctl enable --now podman.socket
        log_info "Enabled rootful podman.socket"
    fi

    # Enable auto-update timer?
    if ui_yesno "Auto-update timer (system-wide)" \
        "Enable podman-auto-update.timer (rootful)?\n\n\
WHAT IT DOES:\n\
  Runs 'podman auto-update' once a day. For every container labeled\n\
  io.containers.autoupdate=registry it pulls the newest image from the\n\
  registry and, if the digest changed, restarts the container's systemd\n\
  unit. Containers without that label are IGNORED.\n\n\
OPT-IN IS PER CONTAINER:\n\
  • Quadlet units: add   Label=io.containers.autoupdate=registry\n\
                  and   AutoUpdate=registry    under [Container]\n\
  • podman run:   add   --label io.containers.autoupdate=registry\n\
  • To pin a container, use AutoUpdate=local (or omit the label).\n\n\
ROOTLESS NOTE:\n\
  This enables only the SYSTEM timer. For rootless users each user must\n\
  run:  systemctl --user enable --now podman-auto-update.timer\n\n\
The built-in quadlet templates (caddy, homepage) are already labeled\n\
for auto-update."; then
        systemctl enable --now podman-auto-update.timer
        log_info "Enabled podman-auto-update.timer"
    fi

    ui_msgbox "Success" "Podman $version installed.\n\nUse the 'rootless' menu to configure per-user containers."

    # Offer rootless setup now
    if ui_yesno "Rootless setup" "Configure rootless podman for a regular user now?"; then
        setup_rootless_user
    fi
}

uninstall_podman() {
    if ! require_root; then
        return 1
    fi

    if ! check_podman_installed; then
        ui_msgbox "Info" "Podman is not installed"
        return
    fi

    if ! ui_yesno "Uninstall Podman" \
        "Are you sure you want to uninstall Podman?\n\n\
This will remove:\n\
- podman, buildah, skopeo, podman-compose, podman-docker, cockpit-podman\n\n\
Container/image data will remain in /var/lib/containers and ~/.local/share/containers."; then
        return
    fi

    # Stop sockets/timers
    systemctl disable --now podman.socket podman-auto-update.timer 2>/dev/null || true

    # Remove packages (ignore missing ones)
    (
        apt-get purge -y podman podman-compose buildah skopeo podman-docker cockpit-podman 2>&1
        apt-get autoremove -y 2>&1
    ) | ui_progressbox "Uninstalling Podman"

    log_info "Podman uninstalled"

    if ui_yesno "Remove Data" \
        "Also remove Podman data?\n\n\
This will delete:\n\
- /var/lib/containers (rootful images/containers)\n\
- $PODMAN_STACKS_DIR (deployed compose stacks)\n\n\
Per-user data under ~/.local/share/containers will NOT be touched."; then
        rm -rf /var/lib/containers "$PODMAN_STACKS_DIR"
        log_info "Podman rootful data removed"
        ui_msgbox "Success" "Podman and rootful data removed."
    else
        ui_msgbox "Success" "Podman removed.\nData preserved."
    fi
}

#=============================================================================
# Rootless setup
#=============================================================================

setup_rootless_user() {
    if ! require_root; then
        return 1
    fi

    # Pick a regular user
    local users_list=()
    while IFS= read -r u; do
        users_list+=("$u" "UID $(id -u "$u")")
    done < <(get_regular_users)

    if [[ ${#users_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No regular users (UID >= 1000) found."
        return
    fi

    local user
    user=$(ui_menu "Select User" "Enable rootless podman for which user?" "${users_list[@]}") || return

    if ! validate_username "$user" || ! user_exists "$user"; then
        ui_msgbox "Error" "Invalid user: $user"
        return 1
    fi

    local uid
    uid=$(id -u "$user")

    # Ensure subuid/subgid entries
    local subuid_ok="yes"
    grep -q "^${user}:" /etc/subuid || subuid_ok="no"
    grep -q "^${user}:" /etc/subgid || subuid_ok="no"

    if [[ "$subuid_ok" == "no" ]]; then
        ui_infobox "Rootless setup" "Allocating subuid/subgid range for $user..."
        if ! usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$user" 2>/dev/null; then
            # Fallback: append manually if usermod doesn't support the flag
            grep -q "^${user}:" /etc/subuid || echo "${user}:100000:65536" >> /etc/subuid
            grep -q "^${user}:" /etc/subgid || echo "${user}:100000:65536" >> /etc/subgid
        fi
        log_info "Allocated subuid/subgid for $user"
    fi

    # Enable lingering so user services run without active login
    if ! loginctl show-user "$user" 2>/dev/null | grep -q "Linger=yes"; then
        loginctl enable-linger "$user"
        log_info "Enabled linger for $user"
    fi

    # Enable user podman.socket
    local output
    output=$(run_as_user "$user" systemctl --user daemon-reload 2>&1)
    output+=$'\n'$(run_as_user "$user" systemctl --user enable --now podman.socket 2>&1)

    # Migrate storage (important after subuid changes)
    run_as_user "$user" podman system migrate 2>/dev/null || true

    local sock_path="/run/user/${uid}/podman/podman.sock"
    local result_msg="Rootless podman configured for: $user\n\n"
    result_msg+="subuid/subgid:  /etc/subuid, /etc/subgid\n"
    result_msg+="Lingering:      enabled\n"
    result_msg+="User socket:    $sock_path\n\n"
    result_msg+="For tools expecting a Docker socket, set:\n"
    result_msg+="  DOCKER_HOST=unix://$sock_path\n\n"
    result_msg+="systemctl output:\n$output"

    ui_msgbox "Rootless Ready" "$result_msg"
}

rootless_show_subids() {
    local info=""
    info+="=== /etc/subuid ===\n"
    info+="$(cat /etc/subuid 2>/dev/null)\n\n"
    info+="=== /etc/subgid ===\n"
    info+="$(cat /etc/subgid 2>/dev/null)\n"

    local tmpfile
    tmpfile=$(mktemp) || return 1
    echo -e "$info" > "$tmpfile"
    ui_textbox "subuid / subgid" "$tmpfile"
    rm -f "$tmpfile"
}

rootless_disable_user() {
    if ! require_root; then
        return 1
    fi

    local users_list=()
    if [[ -d /var/lib/systemd/linger ]]; then
        while IFS= read -r u; do
            [[ -n "$u" ]] && users_list+=("$u" "linger enabled")
        done < <(ls /var/lib/systemd/linger 2>/dev/null)
    fi

    if [[ ${#users_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No users currently have lingering enabled."
        return
    fi

    local user
    user=$(ui_menu "Disable rootless" "Disable rootless podman for which user?" "${users_list[@]}") || return

    if ! user_exists "$user"; then
        ui_msgbox "Error" "User no longer exists: $user"
        return 1
    fi

    run_as_user "$user" systemctl --user disable --now podman.socket 2>/dev/null || true
    loginctl disable-linger "$user"
    log_info "Disabled rootless podman for $user"

    ui_msgbox "Done" "Disabled rootless podman services and linger for $user.\n\n\
subuid/subgid entries and ~/.local/share/containers were NOT removed."
}

manage_rootless() {
    while true; do
        local choice
        choice=$(ui_menu "Rootless Podman" "Select operation:" \
            "enable"  "Enable rootless for a user" \
            "disable" "Disable rootless for a user" \
            "subids"  "Show /etc/subuid and /etc/subgid") || break

        case "$choice" in
            enable)  setup_rootless_user ;;
            disable) rootless_disable_user ;;
            subids)  rootless_show_subids ;;
        esac
    done
}

#=============================================================================
# Service
#=============================================================================

manage_service() {
    if ! check_podman_installed; then
        ui_msgbox "Info" "Podman is not installed"
        return
    fi

    if ! require_root; then
        return 1
    fi

    local choice
    choice=$(ui_menu "Podman Service" "Rootful podman.socket:" \
        "start"   "Start podman.socket" \
        "stop"    "Stop podman.socket" \
        "restart" "Restart podman.socket" \
        "enable"  "Enable on boot" \
        "disable" "Disable on boot") || return

    case "$choice" in
        start)   systemctl start podman.socket;   ui_msgbox "Podman" "podman.socket started" ;;
        stop)    systemctl stop podman.socket;    ui_msgbox "Podman" "podman.socket stopped" ;;
        restart) systemctl restart podman.socket; ui_msgbox "Podman" "podman.socket restarted" ;;
        enable)  systemctl enable podman.socket;  ui_msgbox "Podman" "podman.socket enabled on boot" ;;
        disable) systemctl disable podman.socket; ui_msgbox "Podman" "podman.socket disabled on boot" ;;
    esac

    log_info "Podman service: $choice"
}

#=============================================================================
# Listing / Logs / Prune
#=============================================================================

list_containers() {
    if ! check_podman_installed; then
        ui_msgbox "Info" "Podman is not installed"
        return
    fi

    local info=""
    info+="=== Podman Containers (rootful) ===\n\n"
    info+="$(podman ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}' 2>&1)\n"

    local tmpfile
    tmpfile=$(mktemp) || return 1
    echo -e "$info" > "$tmpfile"
    ui_textbox "Podman Containers" "$tmpfile"
    rm -f "$tmpfile"
}

list_images() {
    if ! check_podman_installed; then
        ui_msgbox "Info" "Podman is not installed"
        return
    fi

    local info=""
    info+="=== Podman Images (rootful) ===\n\n"
    info+="$(podman images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}' 2>&1)\n"

    local tmpfile
    tmpfile=$(mktemp) || return 1
    echo -e "$info" > "$tmpfile"
    ui_textbox "Podman Images" "$tmpfile"
    rm -f "$tmpfile"
}

list_volumes() {
    if ! check_podman_installed; then
        ui_msgbox "Info" "Podman is not installed"
        return
    fi

    local info=""
    info+="=== Podman Volumes (rootful) ===\n\n"
    info+="$(podman volume ls 2>&1)\n"

    local tmpfile
    tmpfile=$(mktemp) || return 1
    echo -e "$info" > "$tmpfile"
    ui_textbox "Podman Volumes" "$tmpfile"
    rm -f "$tmpfile"
}

remove_volume() {
    if ! require_root; then return 1; fi

    local vols_list=()
    while IFS= read -r name; do
        [[ -n "$name" ]] && vols_list+=("$name" "volume")
    done < <(podman volume ls --format '{{.Name}}' 2>/dev/null)

    if [[ ${#vols_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No volumes found"
        return
    fi

    local vol
    vol=$(ui_menu "Remove Volume" "Select volume to remove:" "${vols_list[@]}") || return

    if ! ui_yesno "Confirm" "Remove volume '$vol'?\n\nAll data stored in this volume will be lost."; then
        return
    fi

    local output
    output=$(podman volume rm "$vol" 2>&1)
    if [[ $? -eq 0 ]]; then
        log_info "Removed podman volume: $vol"
        ui_msgbox "Success" "Volume '$vol' removed."
    else
        log_error "Failed to remove podman volume: $vol - $output"
        ui_msgbox "Error" "Failed to remove volume:\n\n$output"
    fi
}

manage_volumes() {
    while true; do
        local choice
        choice=$(ui_menu "Podman Volumes" "Select operation:" \
            "list"   "List volumes" \
            "remove" "Remove a volume") || break

        case "$choice" in
            list)   list_volumes ;;
            remove) remove_volume ;;
        esac
    done
}

view_logs() {
    if ! check_podman_installed; then
        ui_msgbox "Info" "Podman is not installed"
        return
    fi

    local choice
    choice=$(ui_menu "Podman Logs" "Select log source:" \
        "socket"    "Rootful podman.socket logs" \
        "container" "Container logs (rootful)") || return

    case "$choice" in
        socket)
            local logs
            logs=$(journalctl -u podman.socket --no-pager -n 100 2>&1)
            local tmpfile
            tmpfile=$(mktemp) || return 1
            echo "$logs" > "$tmpfile"
            ui_textbox "podman.socket Logs" "$tmpfile"
            rm -f "$tmpfile"
            ;;
        container)
            local containers_list=()
            while IFS= read -r line; do
                local name status
                name=$(echo "$line" | awk '{print $1}')
                status=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
                [[ -n "$name" ]] && containers_list+=("$name" "$status")
            done < <(podman ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null)

            if [[ ${#containers_list[@]} -eq 0 ]]; then
                ui_msgbox "Info" "No containers found"
                return
            fi

            local container
            container=$(ui_menu "Select Container" "Choose container:" "${containers_list[@]}") || return

            local logs
            logs=$(podman logs --tail 100 "$container" 2>&1)
            local tmpfile
            tmpfile=$(mktemp) || return 1
            echo "$logs" > "$tmpfile"
            ui_textbox "Logs: $container" "$tmpfile"
            rm -f "$tmpfile"
            ;;
    esac
}

prune_system() {
    if ! check_podman_installed; then
        ui_msgbox "Info" "Podman is not installed"
        return
    fi

    if ! require_root; then
        return 1
    fi

    local choice
    choice=$(ui_menu "Podman Prune" "Select what to clean:" \
        "all"        "Remove all unused data (containers/images/volumes/networks)" \
        "containers" "Remove stopped containers" \
        "images"     "Remove unused images" \
        "volumes"    "Remove unused volumes" \
        "networks"   "Remove unused networks") || return

    local -a cmd
    local desc=""
    case "$choice" in
        all)        cmd=(podman system prune -a -f --volumes); desc="all unused containers, images, networks, and volumes" ;;
        containers) cmd=(podman container prune -f);           desc="all stopped containers" ;;
        images)     cmd=(podman image prune -a -f);            desc="all unused images" ;;
        volumes)    cmd=(podman volume prune -f);              desc="all unused volumes" ;;
        networks)   cmd=(podman network prune -f);             desc="all unused networks" ;;
    esac

    if ui_yesno "Confirm" "Remove $desc?\n\nThis cannot be undone."; then
        local output
        output=$("${cmd[@]}" 2>&1)
        log_info "Podman prune: $choice"
        ui_msgbox "Prune Complete" "$output"
    fi
}

#=============================================================================
# Networks
#=============================================================================

list_networks() {
    if ! check_podman_installed; then
        ui_msgbox "Info" "Podman is not installed"
        return
    fi

    local info=""
    info+="=== Podman Networks (rootful) ===\n\n"
    info+="$(podman network ls 2>&1)\n"

    local tmpfile
    tmpfile=$(mktemp) || return 1
    echo -e "$info" > "$tmpfile"
    ui_textbox "Podman Networks" "$tmpfile"
    rm -f "$tmpfile"
}

add_network() {
    if ! require_root; then return 1; fi

    local result
    result=$(ui_mixedform "Create Podman Network" \
        "Network Name:" 1 1 "internal" 1 20 30 50 0 \
        "IPv4 Subnet:"  2 1 "10.89.0.0/24" 2 20 30 50 0 \
        "IPv4 Gateway:" 3 1 "10.89.0.1" 3 20 30 50 0) || return

    local network_name ipv4_subnet ipv4_gateway
    network_name=$(echo "$result" | sed -n '1p' | xargs)
    ipv4_subnet=$(echo  "$result" | sed -n '2p' | xargs)
    ipv4_gateway=$(echo "$result" | sed -n '3p' | xargs)

    if [[ -z "$network_name" || -z "$ipv4_subnet" || -z "$ipv4_gateway" ]]; then
        ui_msgbox "Error" "All fields are required"
        return 1
    fi

    if podman network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        ui_msgbox "Error" "Network '$network_name' already exists"
        return 1
    fi

    local enable_ipv6="no"
    local ipv6_subnet=""
    local ipv6_gateway=""
    if ui_yesno "IPv6" "Enable IPv6 for this network?"; then
        enable_ipv6="yes"
        local ipv6_result
        ipv6_result=$(ui_form "IPv6 Configuration" \
            "IPv6 Subnet:"  1 1 "fd00:dead:beaf::/48" 1 20 40 50 \
            "IPv6 Gateway:" 2 1 "fd00:dead:beaf::1"   2 20 40 50) || return
        ipv6_subnet=$(echo  "$ipv6_result" | sed -n '1p' | xargs)
        ipv6_gateway=$(echo "$ipv6_result" | sed -n '2p' | xargs)
        if [[ -z "$ipv6_subnet" || -z "$ipv6_gateway" ]]; then
            ui_msgbox "Error" "All IPv6 fields are required when IPv6 is enabled"
            return 1
        fi
    fi

    local -a cmd=(podman network create --subnet "$ipv4_subnet" --gateway "$ipv4_gateway")
    if [[ "$enable_ipv6" == "yes" ]]; then
        cmd+=(--ipv6 --subnet "$ipv6_subnet" --gateway "$ipv6_gateway")
    fi
    cmd+=("$network_name")

    local output
    output=$("${cmd[@]}" 2>&1)
    if [[ $? -eq 0 ]]; then
        log_info "Created podman network: $network_name"
        ui_msgbox "Success" "Podman network '$network_name' created."
    else
        log_error "Failed to create podman network: $network_name - $output"
        ui_msgbox "Error" "Failed to create network:\n\n$output"
    fi
}

remove_network() {
    if ! require_root; then return 1; fi

    local networks_list=()
    while IFS= read -r name; do
        # Skip default 'podman' network
        [[ -z "$name" || "$name" == "podman" ]] && continue
        networks_list+=("$name" "custom network")
    done < <(podman network ls --format '{{.Name}}' 2>/dev/null)

    if [[ ${#networks_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No custom networks found to remove"
        return
    fi

    local network
    network=$(ui_menu "Remove Network" "Select network to remove:" "${networks_list[@]}") || return

    if ! ui_yesno "Confirm" "Remove network '$network'?"; then
        return
    fi

    local output
    output=$(podman network rm "$network" 2>&1)
    if [[ $? -eq 0 ]]; then
        log_info "Removed podman network: $network"
        ui_msgbox "Success" "Podman network '$network' removed."
    else
        log_error "Failed to remove podman network: $network - $output"
        ui_msgbox "Error" "Failed to remove network:\n\n$output"
    fi
}

manage_networks() {
    while true; do
        local choice
        choice=$(ui_menu "Podman Networks" "Select operation:" \
            "list"   "List networks" \
            "add"    "Add network" \
            "remove" "Remove network") || break

        case "$choice" in
            list)   list_networks ;;
            add)    add_network ;;
            remove) remove_network ;;
        esac
    done
}

#=============================================================================
# Deploy: compose
#=============================================================================

deploy_compose() {
    if ! check_podman_installed; then
        ui_msgbox "Info" "Podman is not installed"
        return
    fi

    if ! require_root; then
        return 1
    fi

    local compose_impl
    compose_impl=$(detect_compose_impl)
    if [[ -z "$compose_impl" ]]; then
        ui_msgbox "Error" \
"No compose implementation found.\n\n\
Podman does not ship a native compose engine — the 'podman compose'\n\
subcommand is a wrapper that requires an external provider.\n\n\
Install one via the podman 'install' menu:\n\
  • podman-compose  (recommended — pure python, no docker)\n\
  • or the docker-compose plugin"
        return 1
    fi

    if [[ ! -d "$PODMAN_COMPOSE_TEMPLATES" ]]; then
        ui_msgbox "Error" "Compose templates directory not found:\n$PODMAN_COMPOSE_TEMPLATES"
        return 1
    fi

    local containers_list=()
    for yml_file in "$PODMAN_COMPOSE_TEMPLATES"/*.yml; do
        [[ -f "$yml_file" ]] || continue
        local name
        name=$(basename "$yml_file" .yml)

        local desc="Podman compose stack"
        local desc_file="$PODMAN_COMPOSE_TEMPLATES/${name}.description"
        [[ -f "$desc_file" ]] && desc=$(cat "$desc_file")

        if [[ -f "$PODMAN_STACKS_DIR/$name/compose.yml" ]]; then
            desc="[DEPLOYED] $desc"
        fi

        containers_list+=("$name" "$desc" "off")
    done

    if [[ ${#containers_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No compose templates found in $PODMAN_COMPOSE_TEMPLATES"
        return
    fi

    local selected
    selected=$(ui_checklist "Deploy Compose Stacks" \
"Select stacks to deploy to $PODMAN_STACKS_DIR (using $compose_impl).\n\n\
The compose file is copied into <target>/compose.yml and brought up\n\
with 'up -d'. To manage later:\n\
   cd $PODMAN_STACKS_DIR/<name>\n\
   podman compose {down|logs|pull|up -d}\n\n\
Compose stacks do NOT participate in podman auto-update by default —\n\
auto-update only acts on containers managed by systemd units. If you\n\
want auto-updates, either use the quadlet deploy option, or add\n\
'labels: [io.containers.autoupdate=registry]' to the service AND\n\
generate a systemd unit for it." \
        "${containers_list[@]}") || return

    [[ -z "$selected" ]] && return

    local confirm_msg="The following stacks will be deployed:\n\n"
    for name in $selected; do
        name=$(echo "$name" | tr -d '"')
        confirm_msg+="  - $name → $PODMAN_STACKS_DIR/$name\n"
    done
    confirm_msg+="\nEach will be started with: "
    if [[ "$compose_impl" == "wrapper" ]]; then
        confirm_msg+="podman compose up -d"
    else
        confirm_msg+="podman-compose up -d"
    fi

    if ! ui_yesno "Confirm Deployment" "$confirm_msg"; then
        return
    fi

    local success_count=0 fail_count=0
    local results=""

    for name in $selected; do
        name=$(echo "$name" | tr -d '"')
        local target_dir="$PODMAN_STACKS_DIR/$name"
        local source_file="$PODMAN_COMPOSE_TEMPLATES/${name}.yml"

        ui_infobox "Deploying" "Deploying $name..."

        if ! mkdir -p "$target_dir"; then
            results+="✗ $name: Failed to create directory\n"
            ((fail_count++))
            continue
        fi

        if ! cp "$source_file" "$target_dir/compose.yml"; then
            results+="✗ $name: Failed to copy compose file\n"
            ((fail_count++))
            continue
        fi

        local output exit_code
        if [[ "$compose_impl" == "wrapper" ]]; then
            output=$(cd "$target_dir" && podman compose up -d 2>&1)
        else
            output=$(cd "$target_dir" && podman-compose up -d 2>&1)
        fi
        exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            results+="✓ $name: Deployed\n"
            log_info "Deployed podman compose stack: $name to $target_dir"
            ((success_count++))
        else
            results+="✗ $name: Failed - $output\n"
            log_error "Failed to deploy podman stack: $name - $output"
            ((fail_count++))
        fi
    done

    local summary="Deployment complete!\n\n"
    summary+="Successful: $success_count\n"
    summary+="Failed: $fail_count\n\n"
    summary+="Results:\n$results"
    ui_msgbox "Deployment Results" "$summary"
}

#=============================================================================
# Deploy: Quadlets
#=============================================================================

deploy_quadlet() {
    if ! check_podman_installed; then
        ui_msgbox "Info" "Podman is not installed"
        return
    fi

    if [[ ! -d "$PODMAN_QUADLET_TEMPLATES" ]]; then
        ui_msgbox "Error" "Quadlet templates directory not found:\n$PODMAN_QUADLET_TEMPLATES"
        return 1
    fi

    # Choose scope
    local scope
    scope=$(ui_menu "Quadlet Scope" "Deploy into which scope?" \
        "rootful"  "System-wide (/etc/containers/systemd/)" \
        "rootless" "Per-user (~/.config/containers/systemd/)") || return

    local target_dir target_user=""
    local daemon_reload_cmd=(systemctl daemon-reload)
    local service_start_cmd_prefix=(systemctl)
    local service_status_cmd_prefix=(systemctl)

    if [[ "$scope" == "rootful" ]]; then
        if ! require_root; then
            return 1
        fi
        target_dir="/etc/containers/systemd"
    else
        if ! is_root; then
            ui_msgbox "Error" "Please run as root — rootless quadlets are installed for a chosen regular user."
            return 1
        fi

        local users_list=()
        while IFS= read -r u; do
            users_list+=("$u" "UID $(id -u "$u")")
        done < <(get_regular_users)

        if [[ ${#users_list[@]} -eq 0 ]]; then
            ui_msgbox "Info" "No regular users found."
            return
        fi

        target_user=$(ui_menu "Target User" "Deploy rootless quadlets for which user?" "${users_list[@]}") || return
        if ! validate_username "$target_user" || ! user_exists "$target_user"; then
            ui_msgbox "Error" "Invalid user: $target_user"
            return 1
        fi

        local home
        home=$(getent passwd "$target_user" | cut -d: -f6)
        target_dir="$home/.config/containers/systemd"

        # daemon-reload and service commands must run as the user
        local uid
        uid=$(id -u "$target_user")
        daemon_reload_cmd=(sudo -u "$target_user" XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user daemon-reload)
        service_start_cmd_prefix=(sudo -u "$target_user" XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user)
        service_status_cmd_prefix=(sudo -u "$target_user" XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user)
    fi

    # Build selectable list (.container, .kube, .pod, .network, .volume)
    local units_list=()
    shopt -s nullglob
    local found_units=("$PODMAN_QUADLET_TEMPLATES"/*.container "$PODMAN_QUADLET_TEMPLATES"/*.kube "$PODMAN_QUADLET_TEMPLATES"/*.pod "$PODMAN_QUADLET_TEMPLATES"/*.network "$PODMAN_QUADLET_TEMPLATES"/*.volume)
    shopt -u nullglob

    local unit_file
    for unit_file in "${found_units[@]}"; do
        [[ -f "$unit_file" ]] || continue
        local base name
        base=$(basename "$unit_file")
        name="${base%.*}"

        local desc="Quadlet unit"
        local desc_file="$PODMAN_QUADLET_TEMPLATES/${name}.description"
        [[ -f "$desc_file" ]] && desc=$(cat "$desc_file")

        if [[ -f "$target_dir/$base" ]]; then
            desc="[DEPLOYED] $desc"
        fi

        units_list+=("$base" "$desc" "off")
    done

    if [[ ${#units_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No quadlet templates found in $PODMAN_QUADLET_TEMPLATES"
        return
    fi

    local selected
    selected=$(ui_checklist "Deploy Quadlets" \
"Select quadlet units to deploy to:\n$target_dir\n\n\
Quadlets are podman-native systemd units. The quadlet generator reads\n\
these files and creates real *.service units on the fly. To stop a unit\n\
use 'systemctl stop <name>.service'; to remove it, delete the file and\n\
run daemon-reload.\n\n\
NOTE: the shipped templates include AutoUpdate=registry and the\n\
io.containers.autoupdate=registry label, so if the auto-update timer\n\
is enabled they will be updated daily. Remove those two lines to pin\n\
a unit to a specific image." \
        "${units_list[@]}") || return

    [[ -z "$selected" ]] && return

    # Ensure target dir exists (with correct ownership for rootless)
    mkdir -p "$target_dir"
    if [[ -n "$target_user" ]]; then
        chown -R "$target_user:$target_user" "$(dirname "$target_dir")"
    fi

    local results=""
    for base in $selected; do
        base=$(echo "$base" | tr -d '"')
        local src="$PODMAN_QUADLET_TEMPLATES/$base"

        if ! cp "$src" "$target_dir/$base"; then
            results+="✗ $base: copy failed\n"
            continue
        fi
        if [[ -n "$target_user" ]]; then
            chown "$target_user:$target_user" "$target_dir/$base"
        fi
        results+="✓ $base copied\n"
        log_info "Deployed quadlet: $target_dir/$base"
    done

    # Reload systemd so quadlet generator picks up new units
    "${daemon_reload_cmd[@]}" 2>&1 || true

    # Offer to start selected services
    if ui_yesno "Start units" "Start the deployed units now via systemd?"; then
        for base in $selected; do
            base=$(echo "$base" | tr -d '"')
            local name="${base%.*}"
            local unit_name="${name}.service"
            local output
            output=$("${service_start_cmd_prefix[@]}" start "$unit_name" 2>&1)
            if [[ $? -eq 0 ]]; then
                results+="✓ $unit_name started\n"
            else
                results+="✗ $unit_name start failed: $output\n"
            fi
        done
    fi

    ui_msgbox "Quadlet Deployment" "$results"
}

#=============================================================================
# Auto-update timer
#=============================================================================

manage_autoupdate() {
    if ! check_podman_installed; then
        ui_msgbox "Info" "Podman is not installed"
        return
    fi

    if ! require_root; then
        return 1
    fi

    local state="disabled"
    if systemctl is-active --quiet podman-auto-update.timer; then
        state="active"
    fi

    local choice
    choice=$(ui_menu "Auto-update (current: $state)" "Select action:" \
        "info"       "How auto-update works & how to opt containers in/out" \
        "enable"     "Enable & start podman-auto-update.timer" \
        "disable"    "Disable & stop podman-auto-update.timer" \
        "status"     "Show timer status and next run" \
        "list"       "List containers currently opted in to auto-update" \
        "run-now"    "Trigger podman auto-update now (dry-run first)") || return

    case "$choice" in
        info)
            local tmpfile
            tmpfile=$(mktemp) || return 1
            cat > "$tmpfile" <<'EOF'
=== How podman auto-update works ===

The podman-auto-update.timer runs once a day (by default). It asks podman
to look at every container that has the label:

    io.containers.autoupdate=<policy>

...and then acts based on the policy:

  registry   Pull the image tag from the registry. If the digest changed,
             restart the container's systemd unit with the new image.
             (Most common choice — use this for rolling updates.)

  local      Only restart the container if a matching newer image is
             already present locally (e.g. built by buildah). Will NOT
             pull from a registry. Use this to "pin" a container to
             images you control.

  image      (Quadlets only) Update when the referenced .image unit
             pulls a new image.

Containers WITHOUT the label are skipped entirely — they will never be
touched by auto-update.

=== How to opt a container IN ===

1) Quadlet unit (/etc/containers/systemd/*.container or
   ~/.config/containers/systemd/*.container):

     [Container]
     Image=ghcr.io/example/app:latest
     AutoUpdate=registry
     Label=io.containers.autoupdate=registry

   (The shipped caddy.container and homepage.container templates
    already have these lines.)

2) podman run:

     podman run -d --name myapp \
       --label io.containers.autoupdate=registry \
       ghcr.io/example/app:latest

3) docker-compose / podman-compose YAML:

     services:
       myapp:
         image: ghcr.io/example/app:latest
         labels:
           io.containers.autoupdate: registry

   NOTE: compose containers are only auto-updated if they are also
   managed by a systemd unit (podman generate systemd, or a quadlet).
   Plain compose-managed containers restart via compose, not systemd,
   so the auto-update tool cannot safely restart them.

=== How to opt a container OUT ===

  • Remove (or never add) the io.containers.autoupdate label.
  • Or set it to 'local' to prevent pulling from a registry.

Changes take effect at the next timer run, or run 'podman auto-update'
manually from this menu.

=== Rootful vs rootless ===

  • This menu manages the system-wide timer (root containers only).
  • Rootless users need their own timer:
        systemctl --user enable --now podman-auto-update.timer
    and rootless auto-update will only touch containers owned by
    that user.

=== Useful commands ===

  podman auto-update --dry-run    # Show what WOULD update, no changes
  podman auto-update              # Apply updates now
  systemctl list-timers podman-auto-update.timer
EOF
            ui_textbox "Auto-update info" "$tmpfile"
            rm -f "$tmpfile"
            ;;
        enable)
            systemctl enable --now podman-auto-update.timer
            log_info "Enabled podman-auto-update.timer"
            ui_msgbox "Auto-update" \
"System timer enabled and started.\n\n\
Remember: only containers labeled\n\
  io.containers.autoupdate=registry (or =local)\n\
will be considered. Unlabeled containers are skipped.\n\n\
Use 'info' for full details, or 'list' to see what is currently opted in."
            ;;
        disable)
            systemctl disable --now podman-auto-update.timer
            log_info "Disabled podman-auto-update.timer"
            ui_msgbox "Auto-update" "Timer disabled and stopped."
            ;;
        status)
            local info
            info=$(systemctl list-timers podman-auto-update.timer --all 2>&1)
            info+=$'\n\n'
            info+=$(systemctl status podman-auto-update.timer --no-pager 2>&1)
            local tmpfile
            tmpfile=$(mktemp) || return 1
            echo "$info" > "$tmpfile"
            ui_textbox "Auto-update Timer" "$tmpfile"
            rm -f "$tmpfile"
            ;;
        list)
            local info
            info="=== Containers opted in to auto-update ===\n\n"
            info+="$(podman ps -a --filter 'label=io.containers.autoupdate' \
                --format 'table {{.Names}}\t{{.Image}}\t{{.Labels}}' 2>&1)\n\n"
            info+="Empty list = no rootful container has the label yet.\n"
            info+="Rootless containers are NOT listed here (check per user)."
            local tmpfile
            tmpfile=$(mktemp) || return 1
            echo -e "$info" > "$tmpfile"
            ui_textbox "Auto-update candidates" "$tmpfile"
            rm -f "$tmpfile"
            ;;
        run-now)
            if ! ui_yesno "Auto-update — dry run first?" \
"Show a DRY RUN first (no changes) so you can review what would happen?\n\n\
Pick 'Yes' for dry-run only, 'No' to apply updates immediately."; then
                local output
                output=$(podman auto-update 2>&1)
                log_info "Triggered podman auto-update manually"
                ui_msgbox "Auto-update run" "$output"
            else
                local output
                output=$(podman auto-update --dry-run 2>&1)
                ui_msgbox "Auto-update (dry-run)" "$output\n\n\
Re-run this menu item and choose 'No' to apply the updates."
            fi
            ;;
    esac
}

#=============================================================================
# Registries config
#=============================================================================

manage_registries() {
    if ! check_podman_installed; then
        ui_msgbox "Info" "Podman is not installed"
        return
    fi

    if ! require_root; then
        return 1
    fi

    if [[ ! -f "$PODMAN_REGISTRIES_CONF" ]]; then
        ui_msgbox "Error" "Registries config not found:\n$PODMAN_REGISTRIES_CONF"
        return 1
    fi

    local current
    current=$(awk '
        /^unqualified-search-registries[[:space:]]*=/ {
            sub(/^unqualified-search-registries[[:space:]]*=[[:space:]]*/, "")
            gsub(/[\[\]"]/, "")
            gsub(/,[[:space:]]*/, " ")
            print
            exit
        }
    ' "$PODMAN_REGISTRIES_CONF")

    [[ -z "$current" ]] && current="docker.io"

    local new_list
    new_list=$(ui_inputbox "Search Registries" \
        "Space-separated list of unqualified-search-registries.\n\
Used when pulling 'alpine' without 'docker.io/library/' prefix.\n\n\
Current:" \
        "$current") || return

    # Validate each hostname
    local host
    for host in $new_list; do
        if [[ ! "$host" =~ ^[a-zA-Z0-9._-]+(:[0-9]+)?$ ]]; then
            ui_msgbox "Error" "Invalid registry hostname: $host"
            return 1
        fi
    done

    # Build TOML array: ["docker.io", "quay.io"]
    local toml_value=""
    local first="yes"
    for host in $new_list; do
        local escaped
        escaped=$(sed_escape "$host")
        if [[ "$first" == "yes" ]]; then
            toml_value="\"${escaped}\""
            first="no"
        else
            toml_value="${toml_value}, \"${escaped}\""
        fi
    done
    toml_value="[${toml_value}]"

    backup_file "$PODMAN_REGISTRIES_CONF" >/dev/null

    if grep -qE '^unqualified-search-registries[[:space:]]*=' "$PODMAN_REGISTRIES_CONF"; then
        sed -i "s|^unqualified-search-registries[[:space:]]*=.*|unqualified-search-registries = ${toml_value}|" "$PODMAN_REGISTRIES_CONF"
    else
        echo "unqualified-search-registries = ${toml_value}" >> "$PODMAN_REGISTRIES_CONF"
    fi

    log_info "Updated unqualified-search-registries: $new_list"
    ui_msgbox "Registries Updated" "unqualified-search-registries set to:\n${toml_value}\n\nBackup saved as ${PODMAN_REGISTRIES_CONF}.bak.*"
}

#=============================================================================
# Main menu
#=============================================================================

module_main() {
    while true; do
        local choice
        choice=$(ui_menu "Podman" "Select operation:" \
            "status"         "Podman status" \
            "install"        "Install Podman (+ optional companions)" \
            "uninstall"      "Uninstall Podman" \
            "rootless"       "Configure rootless podman (per user)" \
            "deploy-compose" "Deploy compose stacks" \
            "deploy-quadlet" "Deploy systemd quadlet units" \
            "containers"     "List containers" \
            "images"         "List images" \
            "volumes"        "Manage volumes" \
            "networks"       "Manage networks" \
            "logs"           "View logs" \
            "prune"          "Clean up unused data" \
            "service"        "Manage podman.socket" \
            "auto-update"    "Auto-update timer" \
            "registries"     "Edit search registries") || break

        case "$choice" in
            status)         podman_status ;;
            install)        install_podman ;;
            uninstall)      uninstall_podman ;;
            rootless)       manage_rootless ;;
            deploy-compose) deploy_compose ;;
            deploy-quadlet) deploy_quadlet ;;
            containers)     list_containers ;;
            images)         list_images ;;
            volumes)        manage_volumes ;;
            networks)       manage_networks ;;
            logs)           view_logs ;;
            prune)          prune_system ;;
            service)        manage_service ;;
            auto-update)    manage_autoupdate ;;
            registries)     manage_registries ;;
        esac
    done
}
