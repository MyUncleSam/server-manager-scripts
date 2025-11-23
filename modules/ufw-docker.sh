#!/bin/bash
#
# Docker UFW Module
# Install and configure ufw-docker from https://github.com/chaifeng/ufw-docker
# Fixes the issue where Docker bypasses UFW firewall rules
#

# Module metadata
module_info() {
    echo "Docker UFW|Configure UFW to work properly with Docker"
}

# UFW-Docker script location
UFW_DOCKER_SCRIPT="/usr/local/bin/ufw-docker"
UFW_AFTER_RULES="/etc/ufw/after.rules"

# Check if ufw-docker is installed
check_ufw_docker_installed() {
    [[ -f "$UFW_DOCKER_SCRIPT" ]]
}

# Check prerequisites
check_prerequisites() {
    # Check UFW
    if ! command_exists ufw; then
        ui_msgbox "UFW Not Installed" "UFW firewall is required but not installed.\n\nPlease install it using the UFW Manager module first."
        return 1
    fi

    # Check Docker
    if ! command_exists docker; then
        ui_msgbox "Missing Prerequisite" "Docker is required but not installed.\n\nPlease install Docker first."
        return 1
    fi

    return 0
}

# Install ufw-docker
install_ufw_docker() {
    if ! require_root; then
        return 1
    fi

    if ! check_prerequisites; then
        return 1
    fi

    if check_ufw_docker_installed; then
        if ! ui_yesno "Already Installed" "ufw-docker is already installed.\n\nDo you want to reinstall?"; then
            return
        fi
    fi

    # Check internet
    if ! has_internet; then
        ui_msgbox "Error" "No internet connection.\nPlease check your network and try again."
        return 1
    fi

    # Explain what will be installed
    local info=""
    info+="This will install ufw-docker from:\n"
    info+="https://github.com/chaifeng/ufw-docker\n\n"
    info+="It will:\n"
    info+="1. Download the ufw-docker script\n"
    info+="2. Modify /etc/ufw/after.rules\n"
    info+="3. Reload UFW\n\n"
    info+="This fixes Docker bypassing UFW firewall rules."

    if ! ui_yesno "Install ufw-docker" "$info"; then
        return
    fi

    # Backup after.rules
    local backup
    backup=$(backup_file "$UFW_AFTER_RULES")
    if [[ -n "$backup" ]]; then
        log_info "Backed up $UFW_AFTER_RULES to $backup"
    fi

    ui_infobox "Installing" "Downloading ufw-docker script..."
    sleep 1

    # Download ufw-docker script
    if ! download_file "https://raw.githubusercontent.com/chaifeng/ufw-docker/master/ufw-docker" "$UFW_DOCKER_SCRIPT"; then
        ui_msgbox "Error" "Failed to download ufw-docker script"
        return 1
    fi

    chmod +x "$UFW_DOCKER_SCRIPT"

    # Install the UFW rules
    ui_infobox "Installing" "Configuring UFW rules..."
    sleep 1

    # Run ufw-docker install
    local output
    output=$("$UFW_DOCKER_SCRIPT" install 2>&1)

    if [[ $? -eq 0 ]]; then
        # Reload UFW
        ufw reload

        log_info "ufw-docker installed successfully"
        ui_msgbox "Success" "ufw-docker installed successfully!\n\nUFW has been reloaded with Docker-compatible rules.\n\nUse 'ufw-docker' command to manage Docker container firewall rules."
    else
        log_error "Failed to install ufw-docker: $output"
        ui_msgbox "Error" "Failed to configure UFW rules.\n\n$output"
    fi
}

# Uninstall ufw-docker
uninstall_ufw_docker() {
    if ! require_root; then
        return 1
    fi

    if ! check_ufw_docker_installed; then
        ui_msgbox "Info" "ufw-docker is not installed"
        return
    fi

    if ! ui_yesno "Uninstall" "Are you sure you want to uninstall ufw-docker?\n\nThis will remove the UFW rules for Docker."; then
        return
    fi

    # Remove the script
    rm -f "$UFW_DOCKER_SCRIPT"

    # Remove Docker rules from after.rules
    # The rules are between markers added by ufw-docker
    if grep -q "ufw-docker" "$UFW_AFTER_RULES"; then
        # Create a cleaned version
        sed -i '/# BEGIN UFW AND DOCKER/,/# END UFW AND DOCKER/d' "$UFW_AFTER_RULES"
        ufw reload
        log_info "Removed ufw-docker rules from $UFW_AFTER_RULES"
    fi

    log_info "ufw-docker uninstalled"
    ui_msgbox "Success" "ufw-docker has been uninstalled.\n\nNote: Docker will now bypass UFW rules again."
}

# Show ufw-docker status
show_status() {
    if ! check_prerequisites; then
        return 1
    fi

    local info=""
    info+="=== UFW-Docker Status ===\n\n"

    # Check if installed
    if check_ufw_docker_installed; then
        info+="Installed:    Yes\n"
        info+="Script:       $UFW_DOCKER_SCRIPT\n"
    else
        info+="Installed:    No\n"
        echo -e "$info" > /tmp/ufw_docker_status.txt
        ui_textbox "UFW-Docker Status" /tmp/ufw_docker_status.txt
        rm -f /tmp/ufw_docker_status.txt
        return
    fi

    # Check if rules are configured
    if grep -q "ufw-docker" "$UFW_AFTER_RULES" 2>/dev/null; then
        info+="UFW Rules:    Configured\n"
    else
        info+="UFW Rules:    Not configured\n"
    fi

    # UFW status
    local ufw_status
    ufw_status=$(ufw status | head -1)
    info+="UFW Status:   $ufw_status\n"

    # Docker status
    if service_is_running docker; then
        info+="Docker:       Running\n"
    else
        info+="Docker:       Stopped\n"
    fi

    # Show allowed containers
    if check_ufw_docker_installed; then
        info+="\n=== Container Rules ===\n\n"
        local rules
        rules=$("$UFW_DOCKER_SCRIPT" list 2>/dev/null)
        if [[ -n "$rules" ]]; then
            info+="$rules\n"
        else
            info+="No container-specific rules configured\n"
        fi
    fi

    echo -e "$info" > /tmp/ufw_docker_status.txt
    ui_textbox "UFW-Docker Status" /tmp/ufw_docker_status.txt
    rm -f /tmp/ufw_docker_status.txt
}

# Allow container access
allow_container() {
    if ! require_root; then
        return 1
    fi

    if ! check_ufw_docker_installed; then
        ui_msgbox "Error" "ufw-docker is not installed"
        return
    fi

    if ! service_is_running docker; then
        ui_msgbox "Error" "Docker is not running"
        return
    fi

    # Get running containers
    local containers
    containers=$(docker ps --format "{{.Names}}" 2>/dev/null)

    if [[ -z "$containers" ]]; then
        ui_msgbox "Info" "No running containers found"
        return
    fi

    # Build menu
    local container_list=()
    while IFS= read -r container; do
        local ports
        ports=$(docker port "$container" 2>/dev/null | head -1)
        container_list+=("$container" "${ports:-no ports}")
    done <<< "$containers"

    # Select container
    local container_name
    container_name=$(ui_menu "Allow Container" "Select container:" "${container_list[@]}") || return

    # Get port
    local port
    port=$(ui_inputbox "Allow Container" "Enter port number to allow (e.g., 80):") || return

    if ! validate_port "$port"; then
        ui_msgbox "Error" "Invalid port number"
        return 1
    fi

    # Get protocol
    local proto
    proto=$(ui_radiolist "Protocol" "Select protocol:" \
        "tcp" "TCP" "on" \
        "udp" "UDP" "off") || return

    # Apply rule
    local output
    output=$("$UFW_DOCKER_SCRIPT" allow "$container_name" "$port/$proto" 2>&1)

    if [[ $? -eq 0 ]]; then
        log_info "Allowed $container_name on port $port/$proto"
        ui_msgbox "Success" "Allowed $container_name on port $port/$proto"
    else
        ui_msgbox "Error" "Failed to add rule:\n$output"
    fi
}

# Delete container rule
delete_rule() {
    if ! require_root; then
        return 1
    fi

    if ! check_ufw_docker_installed; then
        ui_msgbox "Error" "ufw-docker is not installed"
        return
    fi

    # Get current rules
    local rules
    rules=$("$UFW_DOCKER_SCRIPT" list 2>/dev/null)

    if [[ -z "$rules" || "$rules" == *"no rules"* ]]; then
        ui_msgbox "Info" "No container rules to delete"
        return
    fi

    # Show rules and ask for container name
    echo -e "Current rules:\n\n$rules" > /tmp/rules.txt
    ui_textbox "Current Rules" /tmp/rules.txt
    rm -f /tmp/rules.txt

    local container_name
    container_name=$(ui_inputbox "Delete Rule" "Enter container name to delete rules for:") || return

    if [[ -z "$container_name" ]]; then
        return
    fi

    # Delete rules
    local output
    output=$("$UFW_DOCKER_SCRIPT" delete allow "$container_name" 2>&1)

    if [[ $? -eq 0 ]]; then
        log_info "Deleted rules for $container_name"
        ui_msgbox "Success" "Deleted rules for $container_name"
    else
        ui_msgbox "Error" "Failed to delete rules:\n$output"
    fi
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "Docker UFW" "Select operation:" \
            "status" "Show status" \
            "install" "Install ufw-docker" \
            "uninstall" "Uninstall ufw-docker" \
            "allow" "Allow container port" \
            "delete" "Delete container rule") || break

        case "$choice" in
            status)    show_status ;;
            install)   install_ufw_docker ;;
            uninstall) uninstall_ufw_docker ;;
            allow)     allow_container ;;
            delete)    delete_rule ;;
        esac
    done
}
