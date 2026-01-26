#!/bin/bash
#
# Docker Installation Module
# Install Docker using the official convenience script from docker/docker-install
#

# Get the directory where this script is located
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$MODULE_DIR/.." && pwd)"

# Path to module files directory
MODULE_FILES_DIR="$PROJECT_ROOT/modules-files/docker"

# Docker stacks directory
DOCKER_STACKS_DIR="/opt/docker"

# Module metadata
module_info() {
    echo "Docker Install|Install Docker using official script"
}

# Check if Docker is installed
check_docker_installed() {
    command_exists docker
}

# Get Docker version
get_docker_version() {
    docker --version 2>/dev/null | awk '{print $3}' | tr -d ','
}

# Install Docker
install_docker() {
    if ! require_root; then
        return 1
    fi

    if check_docker_installed; then
        local version
        version=$(get_docker_version)
        if ! ui_yesno "Docker Installed" "Docker $version is already installed.\n\nDo you want to reinstall?"; then
            return
        fi
    fi

    # Check internet
    if ! has_internet; then
        ui_msgbox "Error" "No internet connection.\nPlease check your network and try again."
        return 1
    fi

    # Confirm installation
    if ! ui_yesno "Install Docker" "This will install Docker CE using the official script from:\nhttps://github.com/docker/docker-install\n\nProceed with installation?"; then
        return
    fi

    # Download and run installation script
    ui_infobox "Docker Installation" "Downloading Docker installation script..."
    sleep 1

    local temp_script
    temp_script=$(mktemp)

    if ! download_file "https://get.docker.com" "$temp_script"; then
        ui_msgbox "Error" "Failed to download Docker installation script"
        rm -f "$temp_script"
        return 1
    fi

    # Run installation with progress
    chmod +x "$temp_script"

    (
        sh "$temp_script" 2>&1
    ) | ui_progressbox "Installing Docker"

    rm -f "$temp_script"

    # Verify installation
    if check_docker_installed; then
        local version
        version=$(get_docker_version)

        # Enable and start Docker
        systemctl enable docker
        systemctl start docker

        log_info "Docker $version installed successfully"
        ui_msgbox "Success" "Docker $version installed successfully!\n\nDocker service has been enabled and started."

        # Ask about adding user to docker group
        local users_list=()
        while IFS= read -r user; do
            local in_docker="off"
            if id -nG "$user" | grep -qw docker; then
                in_docker="on"
            fi
            users_list+=("$user" "Add to docker group" "$in_docker")
        done < <(get_regular_users)

        if [[ ${#users_list[@]} -gt 0 ]]; then
            local selected_users
            selected_users=$(ui_checklist "Docker Group" "Select users to add to docker group\n(allows running docker without sudo):" "${users_list[@]}") || return 0

            if [[ -n "$selected_users" ]]; then
                for user in $selected_users; do
                    user=$(echo "$user" | tr -d '"')
                    usermod -aG docker "$user"
                    log_info "Added $user to docker group"
                done
                ui_msgbox "Info" "Users added to docker group.\nThey need to log out and back in for changes to take effect."
            fi
        fi
    else
        log_error "Docker installation failed"
        ui_msgbox "Error" "Docker installation failed.\nCheck the logs for details."
    fi
}

# Uninstall Docker
uninstall_docker() {
    if ! require_root; then
        return 1
    fi

    if ! check_docker_installed; then
        ui_msgbox "Info" "Docker is not installed"
        return
    fi

    if ! ui_yesno "Uninstall Docker" "Are you sure you want to uninstall Docker?\n\nThis will remove:\n- Docker Engine\n- Docker CLI\n- containerd\n\nContainers, images, and volumes will remain in /var/lib/docker"; then
        return
    fi

    # Stop Docker
    systemctl stop docker 2>/dev/null || true

    # Remove packages
    (
        apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1
        apt-get autoremove -y 2>&1
    ) | ui_progressbox "Uninstalling Docker"

    log_info "Docker uninstalled"

    # Ask about removing data
    if ui_yesno "Remove Data" "Do you also want to remove Docker data?\n\nThis will delete:\n- /var/lib/docker (images, containers, volumes)\n- /var/lib/containerd"; then
        rm -rf /var/lib/docker /var/lib/containerd
        log_info "Docker data removed"
        ui_msgbox "Success" "Docker and all data removed successfully"
    else
        ui_msgbox "Success" "Docker removed.\nData preserved in /var/lib/docker"
    fi
}

# Show Docker status
docker_status() {
    if ! check_docker_installed; then
        ui_msgbox "Docker Status" "Docker is not installed"
        return
    fi

    local info=""

    # Version
    info+="=== Docker Status ===\n\n"
    info+="Version:      $(get_docker_version)\n"

    # Service status
    local service_status
    if service_is_running docker; then
        service_status="Running"
    else
        service_status="Stopped"
    fi
    info+="Service:      $service_status\n"

    # Docker info
    if service_is_running docker; then
        local containers images
        containers=$(docker info 2>/dev/null | grep "Containers:" | awk '{print $2}')
        images=$(docker info 2>/dev/null | grep "Images:" | awk '{print $2}')
        info+="Containers:   $containers\n"
        info+="Images:       $images\n"

        # Storage driver
        local storage
        storage=$(docker info 2>/dev/null | grep "Storage Driver:" | awk '{print $3}')
        info+="Storage:      $storage\n"

        # Docker root dir
        local docker_root
        docker_root=$(docker info 2>/dev/null | grep "Docker Root Dir:" | awk '{print $4}')
        info+="Root Dir:     $docker_root\n"

        # Disk usage
        local disk_usage
        disk_usage=$(du -sh /var/lib/docker 2>/dev/null | cut -f1)
        info+="Disk Usage:   $disk_usage\n"
    fi

    # Users in docker group
    local docker_users
    docker_users=$(getent group docker | cut -d: -f4)
    info+="\nDocker Group: ${docker_users:-none}\n"

    echo -e "$info" > /tmp/docker_status.txt
    ui_textbox "Docker Status" /tmp/docker_status.txt
    rm -f /tmp/docker_status.txt
}

# Manage Docker service
manage_service() {
    if ! check_docker_installed; then
        ui_msgbox "Info" "Docker is not installed"
        return
    fi

    if ! require_root; then
        return 1
    fi

    local choice
    choice=$(ui_menu "Docker Service" "Select action:" \
        "start" "Start Docker" \
        "stop" "Stop Docker" \
        "restart" "Restart Docker" \
        "enable" "Enable on boot" \
        "disable" "Disable on boot") || return

    case "$choice" in
        start)
            systemctl start docker
            ui_msgbox "Docker" "Docker service started"
            ;;
        stop)
            systemctl stop docker
            ui_msgbox "Docker" "Docker service stopped"
            ;;
        restart)
            systemctl restart docker
            ui_msgbox "Docker" "Docker service restarted"
            ;;
        enable)
            systemctl enable docker
            ui_msgbox "Docker" "Docker enabled on boot"
            ;;
        disable)
            systemctl disable docker
            ui_msgbox "Docker" "Docker disabled on boot"
            ;;
    esac

    log_info "Docker service: $choice"
}

# List containers
list_containers() {
    if ! check_docker_installed; then
        ui_msgbox "Info" "Docker is not installed"
        return
    fi

    if ! service_is_running docker; then
        ui_msgbox "Info" "Docker service is not running"
        return
    fi

    local info=""
    info+="=== Docker Containers ===\n\n"
    info+="$(docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}' 2>&1)\n"

    echo -e "$info" > /tmp/docker_containers.txt
    ui_textbox "Docker Containers" /tmp/docker_containers.txt
    rm -f /tmp/docker_containers.txt
}

# List images
list_images() {
    if ! check_docker_installed; then
        ui_msgbox "Info" "Docker is not installed"
        return
    fi

    if ! service_is_running docker; then
        ui_msgbox "Info" "Docker service is not running"
        return
    fi

    local info=""
    info+="=== Docker Images ===\n\n"
    info+="$(docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}' 2>&1)\n"

    echo -e "$info" > /tmp/docker_images.txt
    ui_textbox "Docker Images" /tmp/docker_images.txt
    rm -f /tmp/docker_images.txt
}

# Prune system
prune_system() {
    if ! check_docker_installed; then
        ui_msgbox "Info" "Docker is not installed"
        return
    fi

    if ! service_is_running docker; then
        ui_msgbox "Info" "Docker service is not running"
        return
    fi

    if ! require_root; then
        return 1
    fi

    local choice
    choice=$(ui_menu "Docker Prune" "Select what to clean:" \
        "all" "Remove all unused data" \
        "containers" "Remove stopped containers" \
        "images" "Remove unused images" \
        "volumes" "Remove unused volumes" \
        "networks" "Remove unused networks") || return

    local cmd=""
    local desc=""
    case "$choice" in
        all)
            cmd="docker system prune -a -f --volumes"
            desc="all unused containers, images, networks, and volumes"
            ;;
        containers)
            cmd="docker container prune -f"
            desc="all stopped containers"
            ;;
        images)
            cmd="docker image prune -a -f"
            desc="all unused images"
            ;;
        volumes)
            cmd="docker volume prune -f"
            desc="all unused volumes"
            ;;
        networks)
            cmd="docker network prune -f"
            desc="all unused networks"
            ;;
    esac

    if ui_yesno "Confirm" "Remove $desc?\n\nThis cannot be undone."; then
        local output
        output=$($cmd 2>&1)
        log_info "Docker prune: $choice"
        ui_msgbox "Prune Complete" "$output"
    fi
}

# View Docker logs
view_logs() {
    if ! check_docker_installed; then
        ui_msgbox "Info" "Docker is not installed"
        return
    fi

    local choice
    choice=$(ui_menu "Docker Logs" "Select log source:" \
        "daemon" "Docker daemon logs" \
        "container" "Container logs") || return

    case "$choice" in
        daemon)
            local logs
            logs=$(journalctl -u docker --no-pager -n 100 2>&1)
            echo "$logs" > /tmp/docker_daemon_logs.txt
            ui_textbox "Docker Daemon Logs" /tmp/docker_daemon_logs.txt
            rm -f /tmp/docker_daemon_logs.txt
            ;;
        container)
            if ! service_is_running docker; then
                ui_msgbox "Info" "Docker service is not running"
                return
            fi

            # Get list of containers
            local containers_list=()
            while IFS= read -r line; do
                local name status
                name=$(echo "$line" | awk '{print $1}')
                status=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
                [[ -n "$name" ]] && containers_list+=("$name" "$status")
            done < <(docker ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null)

            if [[ ${#containers_list[@]} -eq 0 ]]; then
                ui_msgbox "Info" "No containers found"
                return
            fi

            local container
            container=$(ui_menu "Select Container" "Choose container:" "${containers_list[@]}") || return

            local logs
            logs=$(docker logs --tail 100 "$container" 2>&1)
            echo "$logs" > /tmp/docker_container_logs.txt
            ui_textbox "Logs: $container" /tmp/docker_container_logs.txt
            rm -f /tmp/docker_container_logs.txt
            ;;
    esac
}

# List networks
list_networks() {
    if ! check_docker_installed; then
        ui_msgbox "Info" "Docker is not installed"
        return
    fi

    if ! service_is_running docker; then
        ui_msgbox "Info" "Docker service is not running"
        return
    fi

    local info=""
    info+="=== Docker Networks ===\n\n"
    info+="$(docker network ls --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}' 2>&1)\n"

    echo -e "$info" > /tmp/docker_networks.txt
    ui_textbox "Docker Networks" /tmp/docker_networks.txt
    rm -f /tmp/docker_networks.txt
}

# Create a Docker network
add_network() {
    if ! check_docker_installed; then
        ui_msgbox "Info" "Docker is not installed"
        return
    fi

    if ! service_is_running docker; then
        ui_msgbox "Info" "Docker service is not running"
        return
    fi

    if ! require_root; then
        return 1
    fi

    # Get network configuration via form
    local result
    result=$(ui_mixedform "Create Docker Network" \
        "Network Name:" 1 1 "Internal" 1 20 30 50 0 \
        "Driver:" 2 1 "bridge" 2 20 30 50 0 \
        "IPv4 Subnet:" 3 1 "172.20.0.0/16" 3 20 30 50 0 \
        "IPv4 Gateway:" 4 1 "172.20.0.1" 4 20 30 50 0) || return

    # Parse form results (newline separated)
    local network_name driver ipv4_subnet ipv4_gateway
    network_name=$(echo "$result" | sed -n '1p' | xargs)
    driver=$(echo "$result" | sed -n '2p' | xargs)
    ipv4_subnet=$(echo "$result" | sed -n '3p' | xargs)
    ipv4_gateway=$(echo "$result" | sed -n '4p' | xargs)

    # Validate required fields
    if [[ -z "$network_name" ]] || [[ -z "$driver" ]] || [[ -z "$ipv4_subnet" ]] || [[ -z "$ipv4_gateway" ]]; then
        ui_msgbox "Error" "All IPv4 fields are required"
        return 1
    fi

    # Check if network already exists
    if docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        ui_msgbox "Error" "Network '$network_name' already exists"
        return 1
    fi

    # Ask about IPv6
    local enable_ipv6="no"
    local ipv6_subnet=""
    local ipv6_gateway=""

    if ui_yesno "IPv6 Configuration" "Do you want to enable IPv6 for this network?"; then
        enable_ipv6="yes"

        # Get IPv6 configuration
        local ipv6_result
        ipv6_result=$(ui_form "IPv6 Configuration" \
            "IPv6 Subnet:" 1 1 "fd00:dead:beaf::/48" 1 20 40 50 \
            "IPv6 Gateway:" 2 1 "fd00:dead:beaf::1" 2 20 40 50) || return

        ipv6_subnet=$(echo "$ipv6_result" | sed -n '1p' | xargs)
        ipv6_gateway=$(echo "$ipv6_result" | sed -n '2p' | xargs)

        if [[ -z "$ipv6_subnet" ]] || [[ -z "$ipv6_gateway" ]]; then
            ui_msgbox "Error" "All IPv6 fields are required when IPv6 is enabled"
            return 1
        fi
    fi

    # Build confirmation message
    local confirm_msg="Network Name:  $network_name\n"
    confirm_msg+="Driver:        $driver\n"
    confirm_msg+="IPv4 Subnet:   $ipv4_subnet\n"
    confirm_msg+="IPv4 Gateway:  $ipv4_gateway\n"
    if [[ "$enable_ipv6" == "yes" ]]; then
        confirm_msg+="IPv6:          Enabled\n"
        confirm_msg+="IPv6 Subnet:   $ipv6_subnet\n"
        confirm_msg+="IPv6 Gateway:  $ipv6_gateway\n"
    else
        confirm_msg+="IPv6:          Disabled\n"
    fi
    confirm_msg+="\nCreate this network?"

    if ! ui_yesno "Confirm Network Creation" "$confirm_msg"; then
        return
    fi

    # Build docker network create command
    local cmd="docker network create"
    cmd+=" --driver=$driver"
    cmd+=" --subnet=$ipv4_subnet"
    cmd+=" --gateway=$ipv4_gateway"

    if [[ "$enable_ipv6" == "yes" ]]; then
        cmd+=" --ipv6"
        cmd+=" --subnet=$ipv6_subnet"
        cmd+=" --gateway=$ipv6_gateway"
    fi

    cmd+=" $network_name"

    # Create network
    ui_infobox "Creating Network" "Creating Docker network '$network_name'..."
    sleep 1

    local output
    output=$($cmd 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Created Docker network: $network_name"
        ui_msgbox "Success" "Docker network '$network_name' created successfully!"
    else
        log_error "Failed to create Docker network: $network_name - $output"
        ui_msgbox "Error" "Failed to create network:\n\n$output"
        return 1
    fi
}

# Remove a Docker network
remove_network() {
    if ! check_docker_installed; then
        ui_msgbox "Info" "Docker is not installed"
        return
    fi

    if ! service_is_running docker; then
        ui_msgbox "Info" "Docker service is not running"
        return
    fi

    if ! require_root; then
        return 1
    fi

    # Get list of networks (excluding default ones)
    local networks_list=()
    while IFS= read -r line; do
        local name driver scope
        name=$(echo "$line" | awk '{print $1}')
        driver=$(echo "$line" | awk '{print $2}')
        scope=$(echo "$line" | awk '{print $3}')

        # Skip default networks
        if [[ "$name" != "bridge" && "$name" != "host" && "$name" != "none" ]]; then
            networks_list+=("$name" "Driver: $driver, Scope: $scope")
        fi
    done < <(docker network ls --format '{{.Name}} {{.Driver}} {{.Scope}}' 2>/dev/null | tail -n +2)

    if [[ ${#networks_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No custom networks found to remove"
        return
    fi

    local network
    network=$(ui_menu "Remove Network" "Select network to remove:" "${networks_list[@]}") || return

    # Check if network is in use
    local in_use
    in_use=$(docker network inspect "$network" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)

    if [[ -n "$in_use" ]]; then
        if ! ui_yesno "Warning" "Network '$network' is in use by containers:\n$in_use\n\nAre you sure you want to remove it?"; then
            return
        fi
    else
        if ! ui_yesno "Confirm" "Remove network '$network'?"; then
            return
        fi
    fi

    # Remove network
    ui_infobox "Removing Network" "Removing Docker network '$network'..."
    sleep 1

    local output
    output=$(docker network rm "$network" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Removed Docker network: $network"
        ui_msgbox "Success" "Docker network '$network' removed successfully!"
    else
        log_error "Failed to remove Docker network: $network - $output"
        ui_msgbox "Error" "Failed to remove network:\n\n$output"
        return 1
    fi
}

# Manage Docker networks
manage_networks() {
    while true; do
        local choice
        choice=$(ui_menu "Docker Networks" "Select operation:" \
            "list" "List networks" \
            "add" "Add network" \
            "remove" "Remove network") || break

        case "$choice" in
            list)   list_networks ;;
            add)    add_network ;;
            remove) remove_network ;;
        esac
    done
}

# Deploy containers from compose templates
deploy_containers() {
    if ! check_docker_installed; then
        ui_msgbox "Info" "Docker is not installed"
        return
    fi

    if ! service_is_running docker; then
        ui_msgbox "Info" "Docker service is not running"
        return
    fi

    if ! require_root; then
        return 1
    fi

    # Check if module files directory exists
    if [[ ! -d "$MODULE_FILES_DIR" ]]; then
        ui_msgbox "Error" "Module files directory not found:\n$MODULE_FILES_DIR"
        return 1
    fi

    # Build list of available containers
    local containers_list=()
    for yml_file in "$MODULE_FILES_DIR"/*.yml; do
        [[ -f "$yml_file" ]] || continue
        local name
        name=$(basename "$yml_file" .yml)

        # Get description if available
        local desc="Docker container"
        local desc_file="$MODULE_FILES_DIR/${name}.description"
        if [[ -f "$desc_file" ]]; then
            desc=$(cat "$desc_file")
        fi

        # Check if already deployed
        local status="off"
        if [[ -f "$DOCKER_STACKS_DIR/$name/compose.yml" ]]; then
            desc="[DEPLOYED] $desc"
        fi

        containers_list+=("$name" "$desc" "$status")
    done

    if [[ ${#containers_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No container templates found"
        return
    fi

    # Show selection dialog
    local selected
    selected=$(ui_checklist "Deploy Containers" "Select containers to deploy to $DOCKER_STACKS_DIR:" "${containers_list[@]}") || return

    if [[ -z "$selected" ]]; then
        return
    fi

    # Confirm deployment
    local confirm_msg="The following containers will be deployed:\n\n"
    for name in $selected; do
        name=$(echo "$name" | tr -d '"')
        confirm_msg+="  - $name → $DOCKER_STACKS_DIR/$name\n"
    done
    confirm_msg+="\nEach container will be started as a daemon."

    if ! ui_yesno "Confirm Deployment" "$confirm_msg"; then
        return
    fi

    # Deploy each selected container
    local success_count=0
    local fail_count=0
    local results=""

    for name in $selected; do
        name=$(echo "$name" | tr -d '"')
        local target_dir="$DOCKER_STACKS_DIR/$name"
        local source_file="$MODULE_FILES_DIR/${name}.yml"

        ui_infobox "Deploying" "Deploying $name..."

        # Create target directory
        if ! mkdir -p "$target_dir"; then
            results+="✗ $name: Failed to create directory\n"
            ((fail_count++))
            continue
        fi

        # Copy compose file
        if ! cp "$source_file" "$target_dir/compose.yml"; then
            results+="✗ $name: Failed to copy compose file\n"
            ((fail_count++))
            continue
        fi

        # Start container
        local output
        output=$(cd "$target_dir" && docker compose up -d 2>&1)
        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            results+="✓ $name: Deployed successfully\n"
            log_info "Deployed container: $name to $target_dir"
            ((success_count++))
        else
            results+="✗ $name: Failed to start - $output\n"
            log_error "Failed to deploy container: $name - $output"
            ((fail_count++))
        fi
    done

    # Show results
    local summary="Deployment complete!\n\n"
    summary+="Successful: $success_count\n"
    summary+="Failed: $fail_count\n\n"
    summary+="Results:\n$results"

    ui_msgbox "Deployment Results" "$summary"
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "Docker" "Select operation:" \
            "status" "Docker status" \
            "install" "Install Docker" \
            "uninstall" "Uninstall Docker" \
            "deploy" "Deploy containers" \
            "containers" "List containers" \
            "images" "List images" \
            "networks" "Manage networks" \
            "logs" "View logs" \
            "prune" "Clean up unused data" \
            "service" "Manage Docker service") || break

        case "$choice" in
            status)     docker_status ;;
            install)    install_docker ;;
            uninstall)  uninstall_docker ;;
            deploy)     deploy_containers ;;
            containers) list_containers ;;
            images)     list_images ;;
            networks)   manage_networks ;;
            logs)       view_logs ;;
            prune)      prune_system ;;
            service)    manage_service ;;
        esac
    done
}
