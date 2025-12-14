#!/bin/bash
#
# LXD/LXC Module - Install, configure, and manage LXD containers
# Provides comprehensive container management including installation,
# networking, web UI, and full container lifecycle operations
#

# Module metadata - REQUIRED
module_info() {
    echo "LXD Containers|Install and manage LXD/LXC containers"
}

#
# Helper Functions
#

# Check if LXD is installed
check_lxd_installed() {
    snap list lxd &>/dev/null
}

# Get LXD version
get_lxd_version() {
    if check_lxd_installed; then
        lxd --version 2>/dev/null
    else
        echo "Not installed"
    fi
}

# Check if LXD is initialized
check_lxd_initialized() {
    if ! check_lxd_installed; then
        return 1
    fi

    # Try to list storage pools - if this works, LXD is initialized
    lxc storage list &>/dev/null
    return $?
}

# Check if jq is installed (needed for JSON parsing)
check_jq_installed() {
    command_exists jq
}

# Check if LXD service is running
is_lxd_running() {
    if ! check_lxd_installed; then
        return 1
    fi
    service_is_running snap.lxd.daemon
}

#
# Installation Functions
#

# Install LXD
install_lxd() {
    # Check if already installed
    if check_lxd_installed; then
        local version
        version=$(get_lxd_version)
        if ! ui_yesno "LXD Installed" "LXD $version is already installed.\n\nDo you want to reinstall?"; then
            return
        fi
    fi

    # Require root privileges
    if ! require_root; then
        return 1
    fi

    # Check internet connectivity
    if ! has_internet; then
        ui_msgbox "Error" "No internet connection.\nPlease check your network and try again."
        return 1
    fi

    # Confirm installation
    if ! ui_yesno "Install LXD" "This will install LXD via snap.\n\nLXD provides container and virtual machine management with:\n- Full container lifecycle management\n- Advanced networking (bridge, macvlan)\n- Storage pool management\n- Web UI support\n\nProceed with installation?"; then
        return
    fi

    # Install LXD via snap
    snap install lxd 2>&1 | ui_progressbox "Installing LXD" "Installing LXD via snap...\n\nThis may take a few minutes."

    # Install jq if not present (needed for JSON parsing)
    if ! check_jq_installed; then
        apt-get update &>/dev/null
        apt-get install -y jq 2>&1 | ui_progressbox "Installing jq" "Installing jq for JSON parsing..."
    fi

    # Verify installation
    if check_lxd_installed; then
        local version
        version=$(get_lxd_version)
        log_info "LXD $version installed successfully"

        # Show success with version
        ui_msgbox "Installation Complete" "LXD installed successfully!\n\nVersion: $version\n\nPress OK to continue..."

        # Ask to initialize
        if ui_yesno "Initialize LXD" "Do you want to initialize LXD now?\n\nInitialization sets up:\n- Storage pool (default)\n- Network bridge (lxdbr0) with IPv4/IPv6 NAT\n- Default profile for containers\n\nThis is required before creating containers."; then
            initialize_lxd_wizard
        else
            ui_msgbox "Success" "LXD installed successfully!\n\nVersion: $version\n\nYou can initialize it later from the main menu."
        fi
    else
        log_error "LXD installation failed"
        ui_msgbox "Error" "LXD installation failed.\n\nThe snap installation did not complete successfully.\n\nCheck the logs for details."
        return 1
    fi
}

# Initialize LXD with wizard
initialize_lxd_wizard() {
    if ! require_root; then
        return 1
    fi

    if ! check_lxd_installed; then
        ui_msgbox "Error" "LXD is not installed.\n\nPlease install LXD first."
        return 1
    fi

    # Check if already initialized
    if check_lxd_initialized; then
        if ! ui_yesno "Reinitialize" "LXD is already initialized.\n\nReinitializing will reset all configuration.\nExisting containers will NOT be deleted.\n\nContinue?"; then
            return
        fi
    fi

    # Choose initialization method
    local method
    method=$(ui_radiolist "Initialize LXD" "Select initialization method:" \
        "auto" "Automatic (recommended) - Default bridge network with IPv4/IPv6" "on" \
        "manual" "Manual (advanced) - Interactive configuration" "off") || return

    case "$method" in
        auto)
            # Create preseed configuration
            local preseed_file
            preseed_file=$(mktemp)

            cat > "$preseed_file" <<'EOF'
config: {}
networks:
- name: lxdbr0
  type: bridge
  config:
    ipv4.address: auto
    ipv4.nat: "true"
    ipv6.address: auto
    ipv6.nat: "true"
storage_pools:
- name: default
  driver: dir
profiles:
- name: default
  devices:
    root:
      path: /
      pool: default
      type: disk
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
EOF

            ui_infobox "Initializing" "Initializing LXD with default configuration...\n\nThis creates:\n- Bridge network (lxdbr0) with IPv4/IPv6 NAT\n- Storage pool (dir driver)\n- Default profile"
            sleep 2

            local output
            output=$(lxd init --preseed < "$preseed_file" 2>&1)
            local exit_code=$?

            rm -f "$preseed_file"

            if [[ $exit_code -eq 0 ]]; then
                log_info "LXD initialized successfully (auto mode)"
                ui_msgbox "Success" "LXD initialized successfully!\n\nConfiguration:\n- Network: lxdbr0 (bridge with IPv4/IPv6 NAT)\n- Storage: default (dir driver)\n- Profile: default\n\nYou can now create containers!"
            else
                log_error "LXD initialization failed: $output"
                ui_msgbox "Error" "LXD initialization failed.\n\nError: $output"
                return 1
            fi
            ;;

        manual)
            clear
            echo "========================================="
            echo "  LXD Manual Initialization"
            echo "========================================="
            echo ""
            echo "Follow the prompts to configure LXD."
            echo "Press Enter to continue..."
            read -r

            lxd init

            if check_lxd_initialized; then
                log_info "LXD initialized successfully (manual mode)"
                ui_msgbox "Success" "LXD initialized successfully!"
            else
                ui_msgbox "Info" "LXD initialization may have been cancelled or incomplete."
            fi
            ;;
    esac
}

# Uninstall LXD
uninstall_lxd() {
    if ! require_root; then
        return 1
    fi

    if ! check_lxd_installed; then
        ui_msgbox "Info" "LXD is not installed."
        return
    fi

    # Warn about removal
    if ! ui_yesno "Uninstall LXD" "This will remove LXD and stop all containers.\n\nContainers and data will remain in /var/snap/lxd/\nbut will be inaccessible without LXD.\n\nContinue with uninstallation?"; then
        return
    fi

    # Ask about stopping containers
    if check_lxd_initialized; then
        local container_count
        container_count=$(lxc list --format json 2>/dev/null | jq length 2>/dev/null || echo "0")

        if [[ $container_count -gt 0 ]]; then
            if ui_yesno "Stop Containers" "There are $container_count container(s) running.\n\nStop all containers before uninstalling?"; then
                ui_infobox "Stopping Containers" "Stopping all containers..."
                lxc stop --all 2>&1 | ui_progressbox "Stopping Containers"
            fi
        fi
    fi

    # Uninstall LXD
    ui_infobox "Uninstalling" "Removing LXD..."
    sleep 1

    local output
    output=$(snap remove lxd --purge 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "LXD uninstalled successfully"

        # Ask about data removal
        if ui_yesno "Remove Data" "LXD has been uninstalled.\n\nDo you want to remove all LXD data?\n\nThis includes:\n- All containers\n- All images\n- All networks\n- All storage pools\n\nPath: /var/snap/lxd/\n\nThis cannot be undone!"; then
            rm -rf /var/snap/lxd/
            log_info "LXD data removed"
            ui_msgbox "Success" "LXD and all data removed successfully."
        else
            ui_msgbox "Success" "LXD uninstalled.\n\nData preserved in /var/snap/lxd/"
        fi
    else
        log_error "LXD uninstallation failed: $output"
        ui_msgbox "Error" "Failed to uninstall LXD.\n\nError: $output"
    fi
}

#
# Status and Information Functions
#

# Show LXD status
show_lxd_status() {
    if ! check_lxd_installed; then
        ui_msgbox "LXD Status" "LXD is not installed."
        return
    fi

    local info=""
    info+="=== LXD Status ===\n\n"

    # Version
    local version
    version=$(get_lxd_version)
    info+="Version:        $version\n"

    # Service status
    local service_status
    if is_lxd_running; then
        service_status="Running"
    else
        service_status="Stopped"
    fi
    info+="Service:        $service_status\n"

    # Initialization status
    if check_lxd_initialized; then
        info+="Initialized:    Yes\n\n"

        # Storage pools
        local storage_count
        storage_count=$(lxc storage list --format json 2>/dev/null | jq length 2>/dev/null || echo "0")
        info+="Storage Pools:  $storage_count\n"

        # Networks
        local network_count
        network_count=$(lxc network list --format json 2>/dev/null | jq length 2>/dev/null || echo "0")
        info+="Networks:       $network_count\n"

        # Profiles
        local profile_count
        profile_count=$(lxc profile list --format json 2>/dev/null | jq length 2>/dev/null || echo "0")
        info+="Profiles:       $profile_count\n"

        # Containers
        local container_total running_count stopped_count
        container_total=$(lxc list --format json 2>/dev/null | jq length 2>/dev/null || echo "0")
        running_count=$(lxc list --format json 2>/dev/null | jq '[.[] | select(.status=="Running")] | length' 2>/dev/null || echo "0")
        stopped_count=$((container_total - running_count))
        info+="Containers:     $container_total (Running: $running_count, Stopped: $stopped_count)\n"

        # Images
        local image_count
        image_count=$(lxc image list --format json 2>/dev/null | jq length 2>/dev/null || echo "0")
        info+="Images:         $image_count\n"

        # Disk usage
        if [[ -d /var/snap/lxd ]]; then
            local disk_usage
            disk_usage=$(du -sh /var/snap/lxd 2>/dev/null | cut -f1)
            info+="Disk Usage:     $disk_usage\n"
        fi
    else
        info+="Initialized:    No\n\n"
        info+="LXD needs to be initialized before use.\n"
        info+="Use 'Initialize LXD' from the main menu.\n"
    fi

    # Write to temp file and display
    local temp_file
    temp_file=$(mktemp)
    echo -e "$info" > "$temp_file"
    ui_textbox "LXD Status" "$temp_file"
    rm -f "$temp_file"
}

#
# Network Management Functions
#

# Manage networks menu
manage_networks() {
    if ! check_lxd_initialized; then
        ui_msgbox "Error" "LXD is not initialized.\n\nPlease initialize LXD first."
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Network Management" "Select operation:" \
            "list" "List all networks" \
            "create-bridge" "Create bridge network (NAT)" \
            "create-macvlan" "Create macvlan network (physical network)" \
            "info" "Show network details" \
            "remove" "Remove network") || break

        case "$choice" in
            list) list_networks ;;
            create-bridge) create_bridge_network ;;
            create-macvlan) create_macvlan_network ;;
            info) show_network_info ;;
            remove) remove_network ;;
        esac
    done
}

# List networks
list_networks() {
    if ! is_lxd_running; then
        ui_msgbox "Error" "LXD service is not running."
        return 1
    fi

    local info=""
    info+="=== LXD Networks ===\n\n"
    info+="$(lxc network list 2>&1)\n"

    local temp_file
    temp_file=$(mktemp)
    echo -e "$info" > "$temp_file"
    ui_textbox "LXD Networks" "$temp_file"
    rm -f "$temp_file"
}

# Create bridge network
create_bridge_network() {
    if ! require_root; then
        return 1
    fi

    if ! check_lxd_initialized; then
        ui_msgbox "Error" "LXD is not initialized."
        return 1
    fi

    # Get network configuration
    local result
    result=$(ui_mixedform "Create Bridge Network" \
        "Network Name:" 1 1 "lxdbr1" 1 20 30 50 0 \
        "IPv4 Subnet:" 2 1 "10.10.10.1/24" 2 20 30 50 0) || return

    # Parse results
    local network_name ipv4_subnet
    network_name=$(echo "$result" | sed -n '1p' | xargs)
    ipv4_subnet=$(echo "$result" | sed -n '2p' | xargs)

    # Validate required fields
    if [[ -z "$network_name" ]]; then
        ui_msgbox "Error" "Network name is required."
        return 1
    fi

    # Validate network name (alphanumeric, hyphens, lowercase)
    if [[ ! "$network_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        ui_msgbox "Error" "Invalid network name.\n\nName must start with a letter and contain only lowercase letters, numbers, and hyphens."
        return 1
    fi

    # Ask about IPv4 NAT
    local ipv4_nat="true"
    if ! ui_yesno "IPv4 NAT" "Enable IPv4 NAT for this network?\n\nNAT allows containers to access the internet."; then
        ipv4_nat="false"
    fi

    # Ask about IPv6
    local enable_ipv6="no"
    local ipv6_subnet=""
    local ipv6_nat="true"

    if ui_yesno "IPv6 Configuration" "Do you want to enable IPv6 for this network?"; then
        enable_ipv6="yes"

        # Get IPv6 configuration
        local ipv6_result
        ipv6_result=$(ui_inputbox "IPv6 Subnet" "Enter IPv6 subnet:" "fd42:$(printf '%04x' $RANDOM):$(printf '%04x' $RANDOM):$(printf '%04x' $RANDOM)::1/64") || return
        ipv6_subnet=$(echo "$ipv6_result" | xargs)

        if ! ui_yesno "IPv6 NAT" "Enable IPv6 NAT for this network?"; then
            ipv6_nat="false"
        fi
    fi

    # Build confirmation message
    local confirm_msg="Create bridge network with these settings?\n\n"
    confirm_msg+="Name:        $network_name\n"
    confirm_msg+="Type:        Bridge\n"
    confirm_msg+="IPv4:        $ipv4_subnet\n"
    confirm_msg+="IPv4 NAT:    $ipv4_nat\n"
    if [[ "$enable_ipv6" == "yes" ]]; then
        confirm_msg+="IPv6:        $ipv6_subnet\n"
        confirm_msg+="IPv6 NAT:    $ipv6_nat\n"
    else
        confirm_msg+="IPv6:        Disabled\n"
    fi

    if ! ui_yesno "Confirm" "$confirm_msg"; then
        return
    fi

    # Build command
    local cmd="lxc network create $network_name"

    if [[ -n "$ipv4_subnet" ]]; then
        cmd+=" ipv4.address=$ipv4_subnet"
    fi
    cmd+=" ipv4.nat=$ipv4_nat"

    if [[ "$enable_ipv6" == "yes" ]]; then
        cmd+=" ipv6.address=$ipv6_subnet"
        cmd+=" ipv6.nat=$ipv6_nat"
    fi

    # Execute
    ui_infobox "Creating Network" "Creating bridge network '$network_name'..."
    sleep 1

    local output
    output=$($cmd 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Created bridge network: $network_name"
        ui_msgbox "Success" "Bridge network '$network_name' created successfully!\n\nContainers can now use this network."
    else
        log_error "Failed to create bridge network: $output"
        ui_msgbox "Error" "Failed to create bridge network.\n\nError: $output"
        return 1
    fi
}

# Create macvlan network
create_macvlan_network() {
    if ! require_root; then
        return 1
    fi

    if ! check_lxd_initialized; then
        ui_msgbox "Error" "LXD is not initialized."
        return 1
    fi

    # Get physical interfaces
    local interfaces
    interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | grep -v '^lxdbr' | grep -v '@')

    if [[ -z "$interfaces" ]]; then
        ui_msgbox "Error" "No physical network interfaces found."
        return 1
    fi

    # Build interface menu
    local interface_list=()
    for iface in $interfaces; do
        interface_list+=("$iface" "Physical interface")
    done

    # Select parent interface
    local parent_iface
    parent_iface=$(ui_menu "Select Parent Interface" "Choose physical network interface for macvlan:" "${interface_list[@]}") || return

    # Get network name
    local network_name
    network_name=$(ui_inputbox "Network Name" "Enter network name:" "macvlan-$parent_iface") || return

    # Validate network name
    if [[ -z "$network_name" ]]; then
        ui_msgbox "Error" "Network name is required."
        return 1
    fi

    if [[ ! "$network_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        ui_msgbox "Error" "Invalid network name.\n\nName must start with a letter and contain only lowercase letters, numbers, and hyphens."
        return 1
    fi

    # Show warning about macvlan
    if ! ui_yesno "Macvlan Network" "Create macvlan network on $parent_iface?\n\nIMPORTANT:\n- Containers will get IP addresses from your physical network\n- Your network must have a DHCP server\n- Containers will be directly visible on your LAN\n- No NAT is used\n\nName: $network_name\nParent: $parent_iface\n\nContinue?"; then
        return
    fi

    # Create macvlan network
    ui_infobox "Creating Network" "Creating macvlan network '$network_name'..."
    sleep 1

    local output
    output=$(lxc network create "$network_name" --type=macvlan parent="$parent_iface" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Created macvlan network: $network_name (parent: $parent_iface)"
        ui_msgbox "Success" "Macvlan network '$network_name' created successfully!\n\nParent Interface: $parent_iface\n\nContainers using this network will get IPs from your physical network's DHCP server."
    else
        log_error "Failed to create macvlan network: $output"
        ui_msgbox "Error" "Failed to create macvlan network.\n\nError: $output"
        return 1
    fi
}

# Show network info
show_network_info() {
    if ! is_lxd_running; then
        ui_msgbox "Error" "LXD service is not running."
        return 1
    fi

    # Get list of networks
    local networks
    networks=$(lxc network list --format json 2>/dev/null | jq -r '.[].name' 2>/dev/null)

    if [[ -z "$networks" ]]; then
        ui_msgbox "Info" "No networks found."
        return
    fi

    # Build menu
    local network_list=()
    for net in $networks; do
        local net_type
        net_type=$(lxc network show "$net" 2>/dev/null | grep "type:" | awk '{print $2}')
        network_list+=("$net" "$net_type")
    done

    # Select network
    local selected
    selected=$(ui_menu "Network Details" "Select network to view:" "${network_list[@]}") || return

    # Get network info
    local info
    info=$(lxc network show "$selected" 2>&1)

    local temp_file
    temp_file=$(mktemp)
    echo "=== Network: $selected ===" > "$temp_file"
    echo "" >> "$temp_file"
    echo "$info" >> "$temp_file"

    ui_textbox "Network: $selected" "$temp_file"
    rm -f "$temp_file"
}

# Remove network
remove_network() {
    if ! require_root; then
        return 1
    fi

    if ! is_lxd_running; then
        ui_msgbox "Error" "LXD service is not running."
        return 1
    fi

    # Get list of networks (exclude lxdbr0 as it's the default)
    local networks
    networks=$(lxc network list --format json 2>/dev/null | jq -r '[.[] | select(.name != "lxdbr0")] | .[].name' 2>/dev/null)

    if [[ -z "$networks" ]]; then
        ui_msgbox "Info" "No removable networks found.\n\nThe default network (lxdbr0) cannot be removed."
        return
    fi

    # Build menu
    local network_list=()
    for net in $networks; do
        local net_type
        net_type=$(lxc network show "$net" 2>/dev/null | grep "type:" | awk '{print $2}')
        network_list+=("$net" "$net_type")
    done

    # Select network
    local selected
    selected=$(ui_menu "Remove Network" "Select network to remove:" "${network_list[@]}") || return

    # Check if network is in use
    local used_by
    used_by=$(lxc network show "$selected" 2>/dev/null | grep "used_by:" -A 100 | tail -n +2 | grep -v "^config:" | grep -v "^description:" | wc -l)

    if [[ $used_by -gt 0 ]]; then
        if ! ui_yesno "Network In Use" "Network '$selected' is used by $used_by container(s)/profile(s).\n\nRemoving this network may affect container connectivity.\n\nContinue anyway?"; then
            return
        fi
    fi

    # Confirm removal
    if ! ui_yesno "Confirm Removal" "Remove network '$selected'?\n\nThis cannot be undone."; then
        return
    fi

    # Remove network
    ui_infobox "Removing Network" "Removing network '$selected'..."
    sleep 1

    local output
    output=$(lxc network delete "$selected" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Removed network: $selected"
        ui_msgbox "Success" "Network '$selected' removed successfully."
    else
        log_error "Failed to remove network: $output"
        ui_msgbox "Error" "Failed to remove network.\n\nError: $output"
        return 1
    fi
}

#
# Web UI Management Functions
#

# Manage web UI menu
manage_webui() {
    if ! check_lxd_initialized; then
        ui_msgbox "Error" "LXD is not initialized.\n\nPlease initialize LXD first."
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Web UI Management" "Select operation:" \
            "status" "Show web UI status" \
            "enable" "Enable web UI" \
            "disable" "Disable web UI" \
            "password" "Set trust password") || break

        case "$choice" in
            status) show_webui_status ;;
            enable) enable_webui ;;
            disable) disable_webui ;;
            password) set_trust_password ;;
        esac
    done
}

# Show web UI status
show_webui_status() {
    local https_address
    https_address=$(lxc config get core.https_address 2>/dev/null)

    local info=""
    info+="=== Web UI Status ===\n\n"

    if [[ -n "$https_address" ]]; then
        info+="Status:       Enabled\n"
        info+="Address:      https://$https_address\n\n"
        info+="Access the web UI at:\n"
        info+="  https://$https_address\n\n"
        info+="You will need to trust the certificate\n"
        info+="and enter the trust password.\n"
    else
        info+="Status:       Disabled\n\n"
        info+="The web UI is not currently enabled.\n"
        info+="Use 'Enable web UI' to activate it.\n"
    fi

    local temp_file
    temp_file=$(mktemp)
    echo -e "$info" > "$temp_file"
    ui_textbox "Web UI Status" "$temp_file"
    rm -f "$temp_file"
}

# Enable web UI
enable_webui() {
    if ! require_root; then
        return 1
    fi

    # Check if already enabled
    local current_address
    current_address=$(lxc config get core.https_address 2>/dev/null)

    if [[ -n "$current_address" ]]; then
        if ! ui_yesno "Web UI Enabled" "Web UI is already enabled at:\nhttps://$current_address\n\nDo you want to reconfigure it?"; then
            return
        fi
    fi

    # Select listening address
    local listen_address
    listen_address=$(ui_radiolist "Listening Address" "Select listening address:" \
        "127.0.0.1" "Localhost only (secure, local access)" "on" \
        "0.0.0.0" "All interfaces (WARNING: accessible from network)" "off") || return

    # Get port
    local port
    port=$(ui_inputbox "Port" "Enter port for web UI:" "8443") || return

    # Validate port
    if ! validate_port "$port"; then
        ui_msgbox "Error" "Invalid port number.\n\nPort must be between 1 and 65535."
        return 1
    fi

    # Warn if binding to all interfaces
    if [[ "$listen_address" == "0.0.0.0" ]]; then
        if ! ui_yesno "Security Warning" "WARNING: You are about to expose the web UI to ALL network interfaces.\n\nThis means anyone on your network can access the LXD web UI.\n\nRecommendation:\n- Use 127.0.0.1 and access via SSH tunnel\n- Or use a reverse proxy with authentication\n\nContinue with 0.0.0.0?"; then
            return
        fi
    fi

    # Set HTTPS address
    ui_infobox "Configuring" "Enabling web UI on $listen_address:$port..."
    sleep 1

    local output
    output=$(lxc config set core.https_address "$listen_address:$port" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Web UI enabled on $listen_address:$port"

        # Check if trust password is set
        local trust_password_set
        trust_password_set=$(lxc config trust list --format json 2>/dev/null | jq length 2>/dev/null)

        local success_msg="Web UI enabled successfully!\n\n"
        success_msg+="Access at: https://$listen_address:$port\n\n"
        success_msg+="First-time setup:\n"
        success_msg+="1. Navigate to the URL\n"
        success_msg+="2. Accept the certificate warning\n"
        success_msg+="3. Enter trust password\n\n"

        if ui_yesno "Trust Password" "$success_msg\nDo you want to set a trust password now?"; then
            set_trust_password
        fi

        # Offer to add UFW rule if UFW is enabled
        if command_exists ufw; then
            if ufw status | grep -q "Status: active"; then
                if ui_yesno "Firewall Rule" "UFW firewall is active.\n\nDo you want to add a rule to allow port $port?"; then
                    ufw allow "$port/tcp" 2>&1 | ui_progressbox "Adding UFW Rule"
                    log_info "Added UFW rule for port $port"
                    ui_msgbox "Success" "Firewall rule added for port $port."
                fi
            fi
        fi
    else
        log_error "Failed to enable web UI: $output"
        ui_msgbox "Error" "Failed to enable web UI.\n\nError: $output"
        return 1
    fi
}

# Disable web UI
disable_webui() {
    if ! require_root; then
        return 1
    fi

    local current_address
    current_address=$(lxc config get core.https_address 2>/dev/null)

    if [[ -z "$current_address" ]]; then
        ui_msgbox "Info" "Web UI is not currently enabled."
        return
    fi

    if ! ui_yesno "Disable Web UI" "Disable web UI?\n\nCurrently enabled at: https://$current_address"; then
        return
    fi

    ui_infobox "Disabling" "Disabling web UI..."
    sleep 1

    local output
    output=$(lxc config unset core.https_address 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Web UI disabled"
        ui_msgbox "Success" "Web UI disabled successfully."
    else
        log_error "Failed to disable web UI: $output"
        ui_msgbox "Error" "Failed to disable web UI.\n\nError: $output"
    fi
}

# Set trust password
set_trust_password() {
    if ! require_root; then
        return 1
    fi

    local password
    password=$(ui_passwordbox "Trust Password" "Enter trust password for web UI:") || return

    if [[ -z "$password" ]]; then
        ui_msgbox "Error" "Password cannot be empty."
        return 1
    fi

    # Set password
    ui_infobox "Setting Password" "Setting trust password..."
    sleep 1

    local output
    output=$(echo "$password" | lxc config set core.trust_password - 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Trust password set"
        ui_msgbox "Success" "Trust password set successfully.\n\nUse this password when first accessing the web UI."
    else
        log_error "Failed to set trust password: $output"
        ui_msgbox "Error" "Failed to set trust password.\n\nError: $output"
    fi
}

#
# Container Management Functions
#

# Manage containers menu
manage_containers() {
    if ! check_lxd_initialized; then
        ui_msgbox "Error" "LXD is not initialized.\n\nPlease initialize LXD first."
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Container Management" "Select operation:" \
            "list" "List all containers" \
            "create" "Create new container" \
            "start" "Start container" \
            "stop" "Stop container" \
            "restart" "Restart container" \
            "delete" "Delete container" \
            "exec" "Execute shell in container" \
            "info" "Show container information" \
            "logs" "View container logs") || break

        case "$choice" in
            list) list_containers ;;
            create) create_container ;;
            start) start_container ;;
            stop) stop_container ;;
            restart) restart_container ;;
            delete) delete_container ;;
            exec) exec_container ;;
            info) container_info ;;
            logs) container_logs ;;
        esac
    done
}

# List containers
list_containers() {
    if ! is_lxd_running; then
        ui_msgbox "Error" "LXD service is not running."
        return 1
    fi

    local info=""
    info+="=== LXD Containers ===\n\n"
    info+="$(lxc list 2>&1)\n"

    local temp_file
    temp_file=$(mktemp)
    echo -e "$info" > "$temp_file"
    ui_textbox "LXD Containers" "$temp_file"
    rm -f "$temp_file"
}

# Create container
create_container() {
    if ! require_root; then
        return 1
    fi

    if ! check_lxd_initialized; then
        ui_msgbox "Error" "LXD is not initialized."
        return 1
    fi

    # Get container name
    local name
    name=$(ui_inputbox "Container Name" "Enter container name:\n\n(lowercase letters, numbers, hyphens only)") || return

    # Validate name
    if [[ -z "$name" ]]; then
        ui_msgbox "Error" "Container name is required."
        return 1
    fi

    if [[ ! "$name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        ui_msgbox "Error" "Invalid container name.\n\nName must:\n- Start with a lowercase letter\n- Contain only lowercase letters, numbers, and hyphens"
        return 1
    fi

    # Check if name already exists
    if lxc list --format json 2>/dev/null | jq -e ".[] | select(.name==\"$name\")" &>/dev/null; then
        ui_msgbox "Error" "A container named '$name' already exists."
        return 1
    fi

    # Select image source
    local image_source
    image_source=$(ui_menu "Select Image" "Choose base image:" \
        "ubuntu" "Ubuntu LTS" \
        "debian" "Debian" \
        "alpine" "Alpine Linux" \
        "other" "Other (manual)") || return

    local image=""
    case "$image_source" in
        ubuntu)
            local ubuntu_version
            ubuntu_version=$(ui_radiolist "Ubuntu Version" "Select Ubuntu version:" \
                "24.04" "Ubuntu 24.04 LTS (Noble)" "on" \
                "22.04" "Ubuntu 22.04 LTS (Jammy)" "off" \
                "20.04" "Ubuntu 20.04 LTS (Focal)" "off") || return
            image="images:ubuntu/$ubuntu_version"
            ;;
        debian)
            local debian_version
            debian_version=$(ui_radiolist "Debian Version" "Select Debian version:" \
                "12" "Debian 12 (Bookworm)" "on" \
                "11" "Debian 11 (Bullseye)" "off") || return
            image="images:debian/$debian_version"
            ;;
        alpine)
            local alpine_version
            alpine_version=$(ui_radiolist "Alpine Version" "Select Alpine version:" \
                "3.19" "Alpine 3.19" "on" \
                "3.18" "Alpine 3.18" "off" \
                "edge" "Alpine Edge (rolling)" "off") || return
            image="images:alpine/$alpine_version"
            ;;
        other)
            image=$(ui_inputbox "Image Name" "Enter full image name:\n\n(e.g., images:ubuntu/22.04, ubuntu:22.04)") || return
            ;;
    esac

    # Get available networks
    local networks
    networks=$(lxc network list --format json 2>/dev/null | jq -r '.[].name' 2>/dev/null)

    local network=""
    if [[ -n "$networks" ]]; then
        # Build network menu
        local network_list=()
        for net in $networks; do
            network_list+=("$net" "Network")
        done

        network=$(ui_menu "Select Network" "Choose network for container:" "${network_list[@]}") || return
    fi

    # Build confirmation message
    local confirm_msg="Create container with these settings?\n\n"
    confirm_msg+="Name:    $name\n"
    confirm_msg+="Image:   $image\n"
    if [[ -n "$network" ]]; then
        confirm_msg+="Network: $network\n"
    fi

    if ! ui_yesno "Confirm" "$confirm_msg"; then
        return
    fi

    # Build command
    local cmd="lxc launch $image $name"
    if [[ -n "$network" ]]; then
        cmd+=" --network $network"
    fi

    # Create container
    ui_infobox "Creating Container" "Creating container '$name'...\n\nThis may take a few minutes on first run\nas the image needs to be downloaded."
    sleep 1

    local output
    output=$($cmd 2>&1) | ui_progressbox "Creating Container" "Downloading image and creating container..."
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Created container: $name (image: $image)"

        # Get container IP
        sleep 2  # Wait for network to be configured
        local ip_address
        ip_address=$(lxc list "$name" --format json 2>/dev/null | jq -r '.[0].state.network.eth0.addresses[] | select(.family=="inet") | .address' 2>/dev/null)

        local success_msg="Container '$name' created and started successfully!\n\n"
        if [[ -n "$ip_address" ]]; then
            success_msg+="IP Address: $ip_address\n\n"
        fi

        if ui_yesno "Success" "${success_msg}Do you want to open a shell in the container?"; then
            exec_container_direct "$name"
        fi
    else
        log_error "Failed to create container: $output"
        ui_msgbox "Error" "Failed to create container.\n\nError: $output"
        return 1
    fi
}

# Start container
start_container() {
    if ! require_root; then
        return 1
    fi

    # Get stopped containers
    local containers
    containers=$(lxc list --format json 2>/dev/null | jq -r '.[] | select(.status!="Running") | .name' 2>/dev/null)

    if [[ -z "$containers" ]]; then
        ui_msgbox "Info" "No stopped containers found."
        return
    fi

    # Build menu
    local container_list=()
    for cont in $containers; do
        container_list+=("$cont" "Stopped")
    done

    # Select container
    local selected
    selected=$(ui_menu "Start Container" "Select container to start:" "${container_list[@]}") || return

    # Start container
    ui_infobox "Starting" "Starting container '$selected'..."
    sleep 1

    local output
    output=$(lxc start "$selected" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Started container: $selected"
        ui_msgbox "Success" "Container '$selected' started successfully."
    else
        log_error "Failed to start container: $output"
        ui_msgbox "Error" "Failed to start container.\n\nError: $output"
    fi
}

# Stop container
stop_container() {
    if ! require_root; then
        return 1
    fi

    # Get running containers
    local containers
    containers=$(lxc list --format json 2>/dev/null | jq -r '.[] | select(.status=="Running") | .name' 2>/dev/null)

    if [[ -z "$containers" ]]; then
        ui_msgbox "Info" "No running containers found."
        return
    fi

    # Build menu
    local container_list=()
    for cont in $containers; do
        container_list+=("$cont" "Running")
    done

    # Select container
    local selected
    selected=$(ui_menu "Stop Container" "Select container to stop:" "${container_list[@]}") || return

    # Ask about force stop
    local force_flag=""
    if ui_yesno "Stop Method" "How do you want to stop '$selected'?\n\nYes = Graceful shutdown (recommended)\nNo = Force stop"; then
        force_flag=""
    else
        force_flag="--force"
    fi

    # Stop container
    ui_infobox "Stopping" "Stopping container '$selected'..."
    sleep 1

    local output
    output=$(lxc stop "$selected" $force_flag 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Stopped container: $selected"
        ui_msgbox "Success" "Container '$selected' stopped successfully."
    else
        log_error "Failed to stop container: $output"
        ui_msgbox "Error" "Failed to stop container.\n\nError: $output"
    fi
}

# Restart container
restart_container() {
    if ! require_root; then
        return 1
    fi

    # Get running containers
    local containers
    containers=$(lxc list --format json 2>/dev/null | jq -r '.[] | select(.status=="Running") | .name' 2>/dev/null)

    if [[ -z "$containers" ]]; then
        ui_msgbox "Info" "No running containers found."
        return
    fi

    # Build menu
    local container_list=()
    for cont in $containers; do
        container_list+=("$cont" "Running")
    done

    # Select container
    local selected
    selected=$(ui_menu "Restart Container" "Select container to restart:" "${container_list[@]}") || return

    # Restart container
    ui_infobox "Restarting" "Restarting container '$selected'..."
    sleep 1

    local output
    output=$(lxc restart "$selected" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Restarted container: $selected"
        ui_msgbox "Success" "Container '$selected' restarted successfully."
    else
        log_error "Failed to restart container: $output"
        ui_msgbox "Error" "Failed to restart container.\n\nError: $output"
    fi
}

# Delete container
delete_container() {
    if ! require_root; then
        return 1
    fi

    # Get all containers
    local containers
    containers=$(lxc list --format json 2>/dev/null | jq -r '.[].name' 2>/dev/null)

    if [[ -z "$containers" ]]; then
        ui_msgbox "Info" "No containers found."
        return
    fi

    # Build menu
    local container_list=()
    for cont in $containers; do
        local status
        status=$(lxc list --format json 2>/dev/null | jq -r ".[] | select(.name==\"$cont\") | .status" 2>/dev/null)
        container_list+=("$cont" "$status")
    done

    # Select container
    local selected
    selected=$(ui_menu "Delete Container" "Select container to delete:" "${container_list[@]}") || return

    # Check if running
    local status
    status=$(lxc list --format json 2>/dev/null | jq -r ".[] | select(.name==\"$selected\") | .status" 2>/dev/null)

    if [[ "$status" == "Running" ]]; then
        if ! ui_yesno "Container Running" "Container '$selected' is currently running.\n\nDelete anyway? (will force stop)"; then
            return
        fi
    fi

    # Double confirm
    if ! ui_yesno "Confirm Deletion" "Delete container '$selected'?\n\nThis will permanently remove:\n- The container\n- All data inside it\n- All snapshots\n\nThis cannot be undone!\n\nAre you sure?"; then
        return
    fi

    # Delete container
    ui_infobox "Deleting" "Deleting container '$selected'..."
    sleep 1

    local output
    output=$(lxc delete "$selected" --force 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Deleted container: $selected"
        ui_msgbox "Success" "Container '$selected' deleted successfully."
    else
        log_error "Failed to delete container: $output"
        ui_msgbox "Error" "Failed to delete container.\n\nError: $output"
    fi
}

# Execute shell in container (with menu)
exec_container() {
    # Get running containers
    local containers
    containers=$(lxc list --format json 2>/dev/null | jq -r '.[] | select(.status=="Running") | .name' 2>/dev/null)

    if [[ -z "$containers" ]]; then
        ui_msgbox "Info" "No running containers found.\n\nStart a container first."
        return
    fi

    # Build menu
    local container_list=()
    for cont in $containers; do
        container_list+=("$cont" "Running")
    done

    # Select container
    local selected
    selected=$(ui_menu "Execute Shell" "Select container:" "${container_list[@]}") || return

    exec_container_direct "$selected"
}

# Execute shell in container (direct)
exec_container_direct() {
    local container_name="$1"

    # Choose shell
    local shell
    shell=$(ui_radiolist "Select Shell" "Choose shell to execute:" \
        "/bin/bash" "Bash (recommended)" "on" \
        "/bin/sh" "Sh (minimal)" "off" \
        "custom" "Custom command" "off") || return

    if [[ "$shell" == "custom" ]]; then
        shell=$(ui_inputbox "Custom Command" "Enter command to execute:") || return
    fi

    # Clear screen and show instructions
    clear
    echo "========================================="
    echo "  Executing shell in container: $container_name"
    echo "========================================="
    echo ""
    echo "Type 'exit' to return to the menu."
    echo ""
    echo "Press Enter to continue..."
    read -r

    # Execute shell
    lxc exec "$container_name" -- $shell

    # Return to menu
    echo ""
    echo "Exited from container."
    echo "Press Enter to continue..."
    read -r
}

# Show container info
container_info() {
    # Get all containers
    local containers
    containers=$(lxc list --format json 2>/dev/null | jq -r '.[].name' 2>/dev/null)

    if [[ -z "$containers" ]]; then
        ui_msgbox "Info" "No containers found."
        return
    fi

    # Build menu
    local container_list=()
    for cont in $containers; do
        local status
        status=$(lxc list --format json 2>/dev/null | jq -r ".[] | select(.name==\"$cont\") | .status" 2>/dev/null)
        container_list+=("$cont" "$status")
    done

    # Select container
    local selected
    selected=$(ui_menu "Container Information" "Select container:" "${container_list[@]}") || return

    # Get info
    local info
    info=$(lxc info "$selected" 2>&1)

    local temp_file
    temp_file=$(mktemp)
    echo "=== Container: $selected ===" > "$temp_file"
    echo "" >> "$temp_file"
    echo "$info" >> "$temp_file"

    ui_textbox "Container: $selected" "$temp_file"
    rm -f "$temp_file"
}

# View container logs
container_logs() {
    # Get all containers
    local containers
    containers=$(lxc list --format json 2>/dev/null | jq -r '.[].name' 2>/dev/null)

    if [[ -z "$containers" ]]; then
        ui_msgbox "Info" "No containers found."
        return
    fi

    # Build menu
    local container_list=()
    for cont in $containers; do
        local status
        status=$(lxc list --format json 2>/dev/null | jq -r ".[] | select(.name==\"$cont\") | .status" 2>/dev/null)
        container_list+=("$cont" "$status")
    done

    # Select container
    local selected
    selected=$(ui_menu "Container Logs" "Select container:" "${container_list[@]}") || return

    # Get logs
    local logs
    logs=$(lxc info "$selected" --show-log 2>&1)

    local temp_file
    temp_file=$(mktemp)
    echo "=== Logs: $selected ===" > "$temp_file"
    echo "" >> "$temp_file"
    echo "$logs" >> "$temp_file"

    ui_textbox "Logs: $selected" "$temp_file"
    rm -f "$temp_file"
}

#
# Storage Management Functions
#

# Manage storage menu
manage_storage() {
    if ! check_lxd_initialized; then
        ui_msgbox "Error" "LXD is not initialized.\n\nPlease initialize LXD first."
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Storage Management" "Select operation:" \
            "list" "List storage pools" \
            "create" "Create storage pool" \
            "info" "Show pool information" \
            "delete" "Delete storage pool") || break

        case "$choice" in
            list) list_storage_pools ;;
            create) create_storage_pool ;;
            info) show_storage_info ;;
            delete) delete_storage_pool ;;
        esac
    done
}

# List storage pools
list_storage_pools() {
    local info=""
    info+="=== Storage Pools ===\n\n"
    info+="$(lxc storage list 2>&1)\n"

    local temp_file
    temp_file=$(mktemp)
    echo -e "$info" > "$temp_file"
    ui_textbox "Storage Pools" "$temp_file"
    rm -f "$temp_file"
}

# Create storage pool
create_storage_pool() {
    if ! require_root; then
        return 1
    fi

    # Get pool name
    local pool_name
    pool_name=$(ui_inputbox "Pool Name" "Enter storage pool name:") || return

    if [[ -z "$pool_name" ]]; then
        ui_msgbox "Error" "Pool name is required."
        return 1
    fi

    # Validate name
    if [[ ! "$pool_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        ui_msgbox "Error" "Invalid pool name.\n\nName must start with a letter and contain only lowercase letters, numbers, and hyphens."
        return 1
    fi

    # Select driver
    local driver
    driver=$(ui_radiolist "Storage Driver" "Select storage driver:" \
        "dir" "Directory (simple, works everywhere)" "on" \
        "zfs" "ZFS (advanced, requires ZFS)" "off" \
        "btrfs" "Btrfs (requires Btrfs filesystem)" "off" \
        "lvm" "LVM (requires LVM)" "off") || return

    # Build command
    local cmd="lxc storage create $pool_name $driver"

    # Confirm
    if ! ui_yesno "Confirm" "Create storage pool?\n\nName:   $pool_name\nDriver: $driver"; then
        return
    fi

    # Create pool
    ui_infobox "Creating Pool" "Creating storage pool '$pool_name'..."
    sleep 1

    local output
    output=$($cmd 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Created storage pool: $pool_name ($driver)"
        ui_msgbox "Success" "Storage pool '$pool_name' created successfully!"
    else
        log_error "Failed to create storage pool: $output"
        ui_msgbox "Error" "Failed to create storage pool.\n\nError: $output"
        return 1
    fi
}

# Show storage pool info
show_storage_info() {
    # Get pools
    local pools
    pools=$(lxc storage list --format json 2>/dev/null | jq -r '.[].name' 2>/dev/null)

    if [[ -z "$pools" ]]; then
        ui_msgbox "Info" "No storage pools found."
        return
    fi

    # Build menu
    local pool_list=()
    for pool in $pools; do
        local driver
        driver=$(lxc storage show "$pool" 2>/dev/null | grep "driver:" | awk '{print $2}')
        pool_list+=("$pool" "$driver")
    done

    # Select pool
    local selected
    selected=$(ui_menu "Storage Pool Info" "Select pool:" "${pool_list[@]}") || return

    # Get info
    local info
    info=$(lxc storage show "$selected" 2>&1)

    local temp_file
    temp_file=$(mktemp)
    echo "=== Storage Pool: $selected ===" > "$temp_file"
    echo "" >> "$temp_file"
    echo "$info" >> "$temp_file"

    ui_textbox "Pool: $selected" "$temp_file"
    rm -f "$temp_file"
}

# Delete storage pool
delete_storage_pool() {
    if ! require_root; then
        return 1
    fi

    # Get pools (exclude default)
    local pools
    pools=$(lxc storage list --format json 2>/dev/null | jq -r '[.[] | select(.name != "default")] | .[].name' 2>/dev/null)

    if [[ -z "$pools" ]]; then
        ui_msgbox "Info" "No deletable storage pools found.\n\nThe default pool cannot be deleted."
        return
    fi

    # Build menu
    local pool_list=()
    for pool in $pools; do
        local driver
        driver=$(lxc storage show "$pool" 2>/dev/null | grep "driver:" | awk '{print $2}')
        pool_list+=("$pool" "$driver")
    done

    # Select pool
    local selected
    selected=$(ui_menu "Delete Storage Pool" "Select pool to delete:" "${pool_list[@]}") || return

    # Confirm
    if ! ui_yesno "Confirm Deletion" "Delete storage pool '$selected'?\n\nWARNING: This will delete all volumes in this pool.\n\nThis cannot be undone!"; then
        return
    fi

    # Delete pool
    ui_infobox "Deleting Pool" "Deleting storage pool '$selected'..."
    sleep 1

    local output
    output=$(lxc storage delete "$selected" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Deleted storage pool: $selected"
        ui_msgbox "Success" "Storage pool '$selected' deleted successfully."
    else
        log_error "Failed to delete storage pool: $output"
        ui_msgbox "Error" "Failed to delete storage pool.\n\nError: $output"
    fi
}

#
# Profile Management Functions
#

# Manage profiles menu
manage_profiles() {
    if ! check_lxd_initialized; then
        ui_msgbox "Error" "LXD is not initialized.\n\nPlease initialize LXD first."
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Profile Management" "Select operation:" \
            "list" "List profiles" \
            "show" "Show profile configuration" \
            "copy" "Copy profile") || break

        case "$choice" in
            list) list_profiles ;;
            show) show_profile ;;
            copy) copy_profile ;;
        esac
    done
}

# List profiles
list_profiles() {
    local info=""
    info+="=== Profiles ===\n\n"
    info+="$(lxc profile list 2>&1)\n"

    local temp_file
    temp_file=$(mktemp)
    echo -e "$info" > "$temp_file"
    ui_textbox "Profiles" "$temp_file"
    rm -f "$temp_file"
}

# Show profile
show_profile() {
    # Get profiles
    local profiles
    profiles=$(lxc profile list --format json 2>/dev/null | jq -r '.[].name' 2>/dev/null)

    if [[ -z "$profiles" ]]; then
        ui_msgbox "Info" "No profiles found."
        return
    fi

    # Build menu
    local profile_list=()
    for prof in $profiles; do
        profile_list+=("$prof" "Profile")
    done

    # Select profile
    local selected
    selected=$(ui_menu "Show Profile" "Select profile:" "${profile_list[@]}") || return

    # Get profile config
    local config
    config=$(lxc profile show "$selected" 2>&1)

    local temp_file
    temp_file=$(mktemp)
    echo "=== Profile: $selected ===" > "$temp_file"
    echo "" >> "$temp_file"
    echo "$config" >> "$temp_file"

    ui_textbox "Profile: $selected" "$temp_file"
    rm -f "$temp_file"
}

# Copy profile
copy_profile() {
    if ! require_root; then
        return 1
    fi

    # Get profiles
    local profiles
    profiles=$(lxc profile list --format json 2>/dev/null | jq -r '.[].name' 2>/dev/null)

    if [[ -z "$profiles" ]]; then
        ui_msgbox "Info" "No profiles found."
        return
    fi

    # Build menu
    local profile_list=()
    for prof in $profiles; do
        profile_list+=("$prof" "Profile")
    done

    # Select source profile
    local source
    source=$(ui_menu "Copy Profile" "Select source profile:" "${profile_list[@]}") || return

    # Get new name
    local new_name
    new_name=$(ui_inputbox "New Profile Name" "Enter name for new profile:") || return

    if [[ -z "$new_name" ]]; then
        ui_msgbox "Error" "Profile name is required."
        return 1
    fi

    # Copy profile
    ui_infobox "Copying" "Copying profile '$source' to '$new_name'..."
    sleep 1

    local output
    output=$(lxc profile copy "$source" "$new_name" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Copied profile: $source -> $new_name"
        ui_msgbox "Success" "Profile copied successfully!\n\nSource: $source\nNew:    $new_name"
    else
        log_error "Failed to copy profile: $output"
        ui_msgbox "Error" "Failed to copy profile.\n\nError: $output"
    fi
}

#
# Advanced Features
#

# Manage snapshots menu
manage_snapshots() {
    if ! check_lxd_initialized; then
        ui_msgbox "Error" "LXD is not initialized.\n\nPlease initialize LXD first."
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Snapshot Management" "Select operation:" \
            "create" "Create snapshot" \
            "list" "List snapshots" \
            "restore" "Restore snapshot" \
            "delete" "Delete snapshot") || break

        case "$choice" in
            create) create_snapshot ;;
            list) list_snapshots ;;
            restore) restore_snapshot ;;
            delete) delete_snapshot ;;
        esac
    done
}

# Create snapshot
create_snapshot() {
    if ! require_root; then
        return 1
    fi

    # Get containers
    local containers
    containers=$(lxc list --format json 2>/dev/null | jq -r '.[].name' 2>/dev/null)

    if [[ -z "$containers" ]]; then
        ui_msgbox "Info" "No containers found."
        return
    fi

    # Build menu
    local container_list=()
    for cont in $containers; do
        local status
        status=$(lxc list --format json 2>/dev/null | jq -r ".[] | select(.name==\"$cont\") | .status" 2>/dev/null)
        container_list+=("$cont" "$status")
    done

    # Select container
    local selected
    selected=$(ui_menu "Create Snapshot" "Select container:" "${container_list[@]}") || return

    # Get snapshot name
    local snapshot_name
    snapshot_name=$(ui_inputbox "Snapshot Name" "Enter snapshot name:" "snap-$(date +%Y%m%d-%H%M%S)") || return

    if [[ -z "$snapshot_name" ]]; then
        ui_msgbox "Error" "Snapshot name is required."
        return 1
    fi

    # Create snapshot
    ui_infobox "Creating Snapshot" "Creating snapshot '$snapshot_name' of '$selected'..."
    sleep 1

    local output
    output=$(lxc snapshot "$selected" "$snapshot_name" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Created snapshot: $selected/$snapshot_name"
        ui_msgbox "Success" "Snapshot created successfully!\n\nContainer: $selected\nSnapshot: $snapshot_name"
    else
        log_error "Failed to create snapshot: $output"
        ui_msgbox "Error" "Failed to create snapshot.\n\nError: $output"
    fi
}

# List snapshots
list_snapshots() {
    # Get containers
    local containers
    containers=$(lxc list --format json 2>/dev/null | jq -r '.[].name' 2>/dev/null)

    if [[ -z "$containers" ]]; then
        ui_msgbox "Info" "No containers found."
        return
    fi

    # Build menu
    local container_list=()
    for cont in $containers; do
        local status
        status=$(lxc list --format json 2>/dev/null | jq -r ".[] | select(.name==\"$cont\") | .status" 2>/dev/null)
        container_list+=("$cont" "$status")
    done

    # Select container
    local selected
    selected=$(ui_menu "List Snapshots" "Select container:" "${container_list[@]}") || return

    # Get snapshots
    local snapshots
    snapshots=$(lxc info "$selected" 2>&1 | grep -A 100 "Snapshots:" | tail -n +2)

    local temp_file
    temp_file=$(mktemp)
    echo "=== Snapshots: $selected ===" > "$temp_file"
    echo "" >> "$temp_file"
    if [[ -n "$snapshots" ]]; then
        echo "$snapshots" >> "$temp_file"
    else
        echo "No snapshots found." >> "$temp_file"
    fi

    ui_textbox "Snapshots: $selected" "$temp_file"
    rm -f "$temp_file"
}

# Restore snapshot
restore_snapshot() {
    if ! require_root; then
        return 1
    fi

    ui_msgbox "Info" "Snapshot restore functionality.\n\nTo restore a snapshot, use:\nlxc restore <container> <snapshot>\n\nThis feature requires manual execution."
}

# Delete snapshot
delete_snapshot() {
    if ! require_root; then
        return 1
    fi

    ui_msgbox "Info" "Snapshot delete functionality.\n\nTo delete a snapshot, use:\nlxc delete <container>/<snapshot>\n\nThis feature requires manual execution."
}

# Set container resource limits
set_container_limits() {
    if ! require_root; then
        return 1
    fi

    if ! check_lxd_initialized; then
        ui_msgbox "Error" "LXD is not initialized."
        return 1
    fi

    # Get containers
    local containers
    containers=$(lxc list --format json 2>/dev/null | jq -r '.[].name' 2>/dev/null)

    if [[ -z "$containers" ]]; then
        ui_msgbox "Info" "No containers found."
        return
    fi

    # Build menu
    local container_list=()
    for cont in $containers; do
        local status
        status=$(lxc list --format json 2>/dev/null | jq -r ".[] | select(.name==\"$cont\") | .status" 2>/dev/null)
        container_list+=("$cont" "$status")
    done

    # Select container
    local selected
    selected=$(ui_menu "Resource Limits" "Select container:" "${container_list[@]}") || return

    # Get current limits
    local current_cpu current_mem
    current_cpu=$(lxc config get "$selected" limits.cpu 2>/dev/null || echo "unlimited")
    current_mem=$(lxc config get "$selected" limits.memory 2>/dev/null || echo "unlimited")

    # Get new limits
    local result
    result=$(ui_mixedform "Set Resource Limits" \
        "CPU (cores, e.g., 2):" 1 1 "$current_cpu" 1 30 20 50 0 \
        "Memory (e.g., 2GB):" 2 1 "$current_mem" 2 30 20 50 0) || return

    local cpu_limit mem_limit
    cpu_limit=$(echo "$result" | sed -n '1p' | xargs)
    mem_limit=$(echo "$result" | sed -n '2p' | xargs)

    # Apply limits
    ui_infobox "Applying Limits" "Setting resource limits for '$selected'..."
    sleep 1

    local success=true
    if [[ -n "$cpu_limit" ]] && [[ "$cpu_limit" != "unlimited" ]]; then
        if ! lxc config set "$selected" limits.cpu "$cpu_limit" 2>/dev/null; then
            success=false
        fi
    fi

    if [[ -n "$mem_limit" ]] && [[ "$mem_limit" != "unlimited" ]]; then
        if ! lxc config set "$selected" limits.memory "$mem_limit" 2>/dev/null; then
            success=false
        fi
    fi

    if $success; then
        log_info "Set resource limits for $selected: CPU=$cpu_limit, Memory=$mem_limit"
        ui_msgbox "Success" "Resource limits set successfully!\n\nContainer: $selected\nCPU:       $cpu_limit\nMemory:    $mem_limit"
    else
        log_error "Failed to set resource limits for $selected"
        ui_msgbox "Error" "Failed to set resource limits.\n\nCheck the values and try again."
    fi
}

# Configure UFW for LXD
configure_ufw_for_lxd() {
    if ! require_root; then
        return 1
    fi

    if ! command_exists ufw; then
        ui_msgbox "Error" "UFW is not installed.\n\nInstall UFW first using the UFW module."
        return 1
    fi

    if ! ufw status | grep -q "Status: active"; then
        ui_msgbox "Error" "UFW is not active.\n\nEnable UFW first using the UFW module."
        return 1
    fi

    local info=""
    info+="This will configure UFW to allow LXD container traffic.\n\n"
    info+="The following rules will be added:\n"
    info+="- Allow forwarding on lxdbr0\n"
    info+="- Allow traffic from/to LXD bridge\n\n"
    info+="Continue?"

    if ! ui_yesno "Configure UFW" "$info"; then
        return
    fi

    ui_infobox "Configuring UFW" "Adding UFW rules for LXD..."
    sleep 1

    # Add UFW rules for LXD
    ufw allow in on lxdbr0 2>&1 | ui_progressbox "UFW Configuration"
    ufw route allow in on lxdbr0 2>&1 | ui_progressbox "UFW Configuration"

    log_info "Configured UFW for LXD"
    ui_msgbox "Success" "UFW configured for LXD successfully!\n\nContainer traffic is now allowed through the firewall."
}

# Manage LXD service
manage_lxd_service() {
    if ! check_lxd_installed; then
        ui_msgbox "Info" "LXD is not installed."
        return
    fi

    if ! require_root; then
        return 1
    fi

    local choice
    choice=$(ui_menu "LXD Service" "Select action:" \
        "start" "Start LXD service" \
        "stop" "Stop LXD service" \
        "restart" "Restart LXD service" \
        "status" "Show service status") || return

    case "$choice" in
        start)
            systemctl start snap.lxd.daemon
            ui_msgbox "Success" "LXD service started."
            log_info "LXD service started"
            ;;
        stop)
            if ui_yesno "Confirm" "Stop LXD service?\n\nThis will make all containers inaccessible."; then
                systemctl stop snap.lxd.daemon
                ui_msgbox "Success" "LXD service stopped."
                log_info "LXD service stopped"
            fi
            ;;
        restart)
            systemctl restart snap.lxd.daemon
            ui_msgbox "Success" "LXD service restarted."
            log_info "LXD service restarted"
            ;;
        status)
            local status_info
            status_info=$(systemctl status snap.lxd.daemon 2>&1)
            local temp_file
            temp_file=$(mktemp)
            echo "$status_info" > "$temp_file"
            ui_textbox "LXD Service Status" "$temp_file"
            rm -f "$temp_file"
            ;;
    esac
}

#
# Main Module Function
#

# Module main function - REQUIRED
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "LXD Container Management" "Select operation:" \
            "status" "Show LXD status" \
            "install" "Install LXD" \
            "uninstall" "Uninstall LXD" \
            "initialize" "Initialize LXD" \
            "containers" "Manage containers" \
            "networks" "Manage networks" \
            "storage" "Manage storage pools" \
            "profiles" "Manage profiles" \
            "webui" "Manage web UI" \
            "snapshots" "Manage snapshots" \
            "limits" "Set resource limits" \
            "ufw" "Configure UFW for LXD" \
            "service" "Manage LXD service") || break

        case "$choice" in
            status) show_lxd_status ;;
            install) install_lxd ;;
            uninstall) uninstall_lxd ;;
            initialize) initialize_lxd_wizard ;;
            containers) manage_containers ;;
            networks) manage_networks ;;
            storage) manage_storage ;;
            profiles) manage_profiles ;;
            webui) manage_webui ;;
            snapshots) manage_snapshots ;;
            limits) set_container_limits ;;
            ufw) configure_ufw_for_lxd ;;
            service) manage_lxd_service ;;
        esac
    done
}
