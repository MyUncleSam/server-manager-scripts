#!/bin/bash
#
# Docker Installation Module
# Install Docker using the official convenience script from docker/docker-install
#

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

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "Docker" "Select operation:" \
            "status" "Docker status" \
            "install" "Install Docker" \
            "uninstall" "Uninstall Docker" \
            "containers" "List containers" \
            "images" "List images" \
            "logs" "View logs" \
            "prune" "Clean up unused data" \
            "service" "Manage Docker service") || break

        case "$choice" in
            status)     docker_status ;;
            install)    install_docker ;;
            uninstall)  uninstall_docker ;;
            containers) list_containers ;;
            images)     list_images ;;
            logs)       view_logs ;;
            prune)      prune_system ;;
            service)    manage_service ;;
        esac
    done
}
