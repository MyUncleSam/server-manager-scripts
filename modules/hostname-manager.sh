#!/bin/bash
#
# Hostname Manager Module
# Configure system hostname and related settings
#

# Module metadata
module_info() {
    echo "Hostname Manager|Configure hostname and hosts file"
}

# Show current hostname info
show_hostname_info() {
    local info=""
    info+="=== Hostname Information ===\n\n"

    # Current hostnames
    info+="Hostname:        $(hostname)\n"
    info+="FQDN:            $(hostname -f 2>/dev/null || echo 'Not set')\n"
    info+="Short name:      $(hostname -s 2>/dev/null || echo 'Not set')\n"

    # Static hostname (systemd)
    if command_exists hostnamectl; then
        info+="\n=== Hostnamectl Status ===\n\n"
        local hctl_status
        hctl_status=$(hostnamectl status 2>&1)
        info+="$hctl_status\n"
    fi

    # Hosts file entries
    info+="\n=== /etc/hosts ===\n\n"
    info+="$(cat /etc/hosts)\n"

    echo -e "$info" > /tmp/hostname_info.txt
    ui_textbox "Hostname Information" /tmp/hostname_info.txt
    rm -f /tmp/hostname_info.txt
}

# Set hostname
set_hostname() {
    if ! require_root; then
        return 1
    fi

    local current_hostname
    current_hostname=$(hostname)

    local new_hostname
    new_hostname=$(ui_inputbox "Set Hostname" "Enter new hostname:" "$current_hostname") || return

    if [[ -z "$new_hostname" ]]; then
        ui_msgbox "Error" "Hostname cannot be empty"
        return 1
    fi

    # Validate hostname
    if [[ ! "$new_hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        ui_msgbox "Error" "Invalid hostname format.\n\nHostname must:\n- Start with a letter or number\n- Contain only letters, numbers, and hyphens\n- Be 1-63 characters long\n- Not end with a hyphen"
        return 1
    fi

    # Ask about hostname type
    local hostname_type
    hostname_type=$(ui_radiolist "Hostname Type" "Select hostname type to set:" \
        "all" "All (static, transient, pretty)" "on" \
        "static" "Static only" "off" \
        "transient" "Transient only" "off" \
        "pretty" "Pretty only" "off") || return

    # Set the hostname
    local cmd_result
    if [[ "$hostname_type" == "all" ]]; then
        cmd_result=$(hostnamectl set-hostname "$new_hostname" 2>&1)
    else
        cmd_result=$(hostnamectl set-hostname "$new_hostname" --$hostname_type 2>&1)
    fi

    if [[ $? -eq 0 ]]; then
        log_info "Hostname changed from '$current_hostname' to '$new_hostname'"

        # Ask to update /etc/hosts
        if ui_yesno "Update Hosts" "Update /etc/hosts with new hostname?"; then
            update_hosts_file "$current_hostname" "$new_hostname"
        fi

        ui_msgbox "Success" "Hostname changed to: $new_hostname\n\nNote: You may need to log out and back in for all changes to take effect."
    else
        ui_msgbox "Error" "Failed to set hostname:\n$cmd_result"
    fi
}

# Update /etc/hosts file
update_hosts_file() {
    local old_hostname="$1"
    local new_hostname="$2"

    # Backup hosts file
    backup_file "/etc/hosts"

    # Replace old hostname with new one
    sed -i "s/\b$old_hostname\b/$new_hostname/g" /etc/hosts

    # Ensure localhost entries exist
    if ! grep -q "127.0.0.1.*localhost" /etc/hosts; then
        echo "127.0.0.1 localhost" >> /etc/hosts
    fi

    if ! grep -q "127.0.1.1.*$new_hostname" /etc/hosts; then
        echo "127.0.1.1 $new_hostname" >> /etc/hosts
    fi

    log_info "Updated /etc/hosts with hostname: $new_hostname"
}

# Set pretty hostname
set_pretty_hostname() {
    if ! require_root; then
        return 1
    fi

    local current_pretty
    current_pretty=$(hostnamectl --pretty 2>/dev/null)

    local new_pretty
    new_pretty=$(ui_inputbox "Pretty Hostname" "Enter pretty hostname (can include spaces and special characters):" "$current_pretty") || return

    if hostnamectl set-hostname "$new_pretty" --pretty; then
        log_info "Pretty hostname set to: $new_pretty"
        ui_msgbox "Success" "Pretty hostname set to: $new_pretty"
    else
        ui_msgbox "Error" "Failed to set pretty hostname"
    fi
}

# Edit hosts file
edit_hosts_file() {
    if ! require_root; then
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Edit Hosts" "Select operation:" \
            "view" "View hosts file" \
            "add" "Add entry" \
            "remove" "Remove entry" \
            "edit" "Edit entry") || break

        case "$choice" in
            view)
                ui_textbox "/etc/hosts" /etc/hosts
                ;;
            add)
                add_hosts_entry
                ;;
            remove)
                remove_hosts_entry
                ;;
            edit)
                edit_hosts_entry
                ;;
        esac
    done
}

# Add hosts entry
add_hosts_entry() {
    local ip
    ip=$(ui_inputbox "Add Host Entry" "Enter IP address:") || return

    if ! validate_ip "$ip"; then
        ui_msgbox "Error" "Invalid IP address"
        return 1
    fi

    local hostnames
    hostnames=$(ui_inputbox "Add Host Entry" "Enter hostname(s) (space-separated):") || return

    if [[ -z "$hostnames" ]]; then
        ui_msgbox "Error" "Hostname cannot be empty"
        return 1
    fi

    # Backup and add entry
    backup_file "/etc/hosts"
    echo "$ip $hostnames" >> /etc/hosts

    log_info "Added hosts entry: $ip $hostnames"
    ui_msgbox "Success" "Added entry:\n$ip $hostnames"
}

# Remove hosts entry
remove_hosts_entry() {
    # Get current entries (excluding comments and empty lines)
    local entries
    entries=$(grep -v "^#" /etc/hosts | grep -v "^$" | nl -ba)

    if [[ -z "$entries" ]]; then
        ui_msgbox "Info" "No entries to remove"
        return
    fi

    echo -e "Current entries:\n\n$entries" > /tmp/hosts_entries.txt
    ui_textbox "Hosts Entries" /tmp/hosts_entries.txt
    rm -f /tmp/hosts_entries.txt

    local line_num
    line_num=$(ui_inputbox "Remove Entry" "Enter line number to remove:") || return

    if [[ ! "$line_num" =~ ^[0-9]+$ ]]; then
        ui_msgbox "Error" "Invalid line number"
        return 1
    fi

    # Get the line content for confirmation
    local line_content
    line_content=$(grep -v "^#" /etc/hosts | grep -v "^$" | sed -n "${line_num}p")

    if [[ -z "$line_content" ]]; then
        ui_msgbox "Error" "Line not found"
        return 1
    fi

    if ui_yesno "Confirm" "Remove this entry?\n\n$line_content"; then
        backup_file "/etc/hosts"

        # Remove the line (accounting for comments)
        local actual_line
        actual_line=$(grep -n "^$line_content$" /etc/hosts | head -1 | cut -d: -f1)
        sed -i "${actual_line}d" /etc/hosts

        log_info "Removed hosts entry: $line_content"
        ui_msgbox "Success" "Entry removed"
    fi
}

# Edit hosts entry
edit_hosts_entry() {
    local entries
    entries=$(grep -v "^#" /etc/hosts | grep -v "^$" | nl -ba)

    if [[ -z "$entries" ]]; then
        ui_msgbox "Info" "No entries to edit"
        return
    fi

    echo -e "Current entries:\n\n$entries" > /tmp/hosts_entries.txt
    ui_textbox "Hosts Entries" /tmp/hosts_entries.txt
    rm -f /tmp/hosts_entries.txt

    local line_num
    line_num=$(ui_inputbox "Edit Entry" "Enter line number to edit:") || return

    if [[ ! "$line_num" =~ ^[0-9]+$ ]]; then
        ui_msgbox "Error" "Invalid line number"
        return 1
    fi

    local line_content
    line_content=$(grep -v "^#" /etc/hosts | grep -v "^$" | sed -n "${line_num}p")

    if [[ -z "$line_content" ]]; then
        ui_msgbox "Error" "Line not found"
        return 1
    fi

    local new_content
    new_content=$(ui_inputbox "Edit Entry" "Edit entry:" "$line_content") || return

    if [[ -z "$new_content" ]]; then
        ui_msgbox "Error" "Entry cannot be empty"
        return 1
    fi

    backup_file "/etc/hosts"

    # Replace the line
    local actual_line
    actual_line=$(grep -n "^$line_content$" /etc/hosts | head -1 | cut -d: -f1)
    sed -i "${actual_line}s/.*/$new_content/" /etc/hosts

    log_info "Edited hosts entry: $line_content -> $new_content"
    ui_msgbox "Success" "Entry updated"
}

# Set chassis type
set_chassis() {
    if ! require_root; then
        return 1
    fi

    local chassis
    chassis=$(ui_menu "Chassis Type" "Select chassis type:" \
        "desktop" "Desktop" \
        "laptop" "Laptop" \
        "convertible" "Convertible" \
        "server" "Server" \
        "tablet" "Tablet" \
        "handset" "Handset" \
        "watch" "Watch" \
        "embedded" "Embedded" \
        "vm" "Virtual Machine" \
        "container" "Container") || return

    if hostnamectl set-chassis "$chassis"; then
        log_info "Chassis type set to: $chassis"
        ui_msgbox "Success" "Chassis type set to: $chassis"
    else
        ui_msgbox "Error" "Failed to set chassis type"
    fi
}

# Set deployment environment
set_deployment() {
    if ! require_root; then
        return 1
    fi

    local deployment
    deployment=$(ui_menu "Deployment" "Select deployment environment:" \
        "development" "Development" \
        "integration" "Integration" \
        "staging" "Staging" \
        "production" "Production") || return

    if hostnamectl set-deployment "$deployment"; then
        log_info "Deployment set to: $deployment"
        ui_msgbox "Success" "Deployment environment set to: $deployment"
    else
        ui_msgbox "Error" "Failed to set deployment environment"
    fi
}

# Set location
set_location() {
    if ! require_root; then
        return 1
    fi

    local location
    location=$(ui_inputbox "Location" "Enter location (e.g., 'Rack 5, Datacenter A'):") || return

    if hostnamectl set-location "$location"; then
        log_info "Location set to: $location"
        ui_msgbox "Success" "Location set to: $location"
    else
        ui_msgbox "Error" "Failed to set location"
    fi
}

# Set icon name
set_icon() {
    if ! require_root; then
        return 1
    fi

    local icon
    icon=$(ui_inputbox "Icon Name" "Enter icon name (e.g., 'computer-server'):") || return

    if hostnamectl set-icon-name "$icon"; then
        log_info "Icon name set to: $icon"
        ui_msgbox "Success" "Icon name set to: $icon"
    else
        ui_msgbox "Error" "Failed to set icon name"
    fi
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "Hostname Manager" "Select operation:" \
            "info" "Show hostname information" \
            "set" "Set hostname" \
            "pretty" "Set pretty hostname" \
            "hosts" "Edit /etc/hosts" \
            "chassis" "Set chassis type" \
            "deployment" "Set deployment environment" \
            "location" "Set location" \
            "icon" "Set icon name") || break

        case "$choice" in
            info)       show_hostname_info ;;
            set)        set_hostname ;;
            pretty)     set_pretty_hostname ;;
            hosts)      edit_hosts_file ;;
            chassis)    set_chassis ;;
            deployment) set_deployment ;;
            location)   set_location ;;
            icon)       set_icon ;;
        esac
    done
}
