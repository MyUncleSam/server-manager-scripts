#!/bin/bash
#
# UFW Manager Module
# Manage UFW firewall rules and settings
#

# Module metadata
module_info() {
    echo "UFW Manager|Manage UFW firewall rules and settings"
}

# Check if UFW is installed
check_ufw_installed() {
    if ! command_exists ufw; then
        if ui_yesno "UFW Not Installed" "UFW firewall is not installed.\n\nWould you like to install it now?"; then
            if ! require_root; then
                return 1
            fi
            ui_infobox "Installing" "Installing UFW..."
            if install_packages ufw; then
                log_info "UFW installed successfully"
                ui_msgbox "Success" "UFW installed successfully"
            else
                ui_msgbox "Error" "Failed to install UFW"
                return 1
            fi
        else
            return 1
        fi
    fi
    return 0
}

# Install UFW
install_ufw() {
    if command_exists ufw; then
        ui_msgbox "Info" "UFW is already installed"
        return 0
    fi

    if ! require_root; then
        return 1
    fi

    if ui_yesno "Install UFW" "Would you like to install UFW firewall?"; then
        ui_infobox "Installing" "Installing UFW..."
        if install_packages ufw; then
            log_info "UFW installed successfully"
            ui_msgbox "Success" "UFW installed successfully.\n\nUse 'Enable UFW' to activate it."
        else
            ui_msgbox "Error" "Failed to install UFW"
            return 1
        fi
    fi
}

# Show UFW status
show_status() {
    if ! check_ufw_installed; then
        return 1
    fi

    local status
    status=$(ufw status verbose 2>&1)

    echo "$status" > /tmp/ufw_status.txt
    ui_textbox "UFW Status" /tmp/ufw_status.txt
    rm -f /tmp/ufw_status.txt
}

# Enable UFW
enable_ufw() {
    if ! require_root; then
        return 1
    fi

    if ! check_ufw_installed; then
        return 1
    fi

    if ui_yesno "Enable UFW" "Are you sure you want to enable UFW?\n\nWarning: This may disrupt existing SSH connections if port 22 is not allowed."; then
        local output
        output=$(ufw --force enable 2>&1)

        if [[ $? -eq 0 ]]; then
            log_info "UFW enabled"
            ui_msgbox "Success" "UFW has been enabled.\n\n$output"
        else
            ui_msgbox "Error" "Failed to enable UFW:\n$output"
        fi
    fi
}

# Disable UFW
disable_ufw() {
    if ! require_root; then
        return 1
    fi

    if ! check_ufw_installed; then
        return 1
    fi

    if ui_yesno "Disable UFW" "Are you sure you want to disable UFW?\n\nThis will leave your system without firewall protection."; then
        local output
        output=$(ufw disable 2>&1)

        if [[ $? -eq 0 ]]; then
            log_info "UFW disabled"
            ui_msgbox "Success" "UFW has been disabled."
        else
            ui_msgbox "Error" "Failed to disable UFW:\n$output"
        fi
    fi
}

# Add allow rule
add_allow_rule() {
    if ! require_root; then
        return 1
    fi

    if ! check_ufw_installed; then
        return 1
    fi

    local rule_type
    rule_type=$(ui_menu "Add Allow Rule" "Select rule type:" \
        "port" "Allow specific port" \
        "service" "Allow service by name" \
        "ip" "Allow from IP address" \
        "subnet" "Allow from subnet") || return

    case "$rule_type" in
        port)
            local port
            port=$(ui_inputbox "Allow Port" "Enter port number (e.g., 80, 443, 8080):") || return

            if ! validate_port "$port"; then
                ui_msgbox "Error" "Invalid port number"
                return 1
            fi

            local proto
            proto=$(ui_radiolist "Protocol" "Select protocol:" \
                "tcp" "TCP" "on" \
                "udp" "UDP" "off" \
                "both" "TCP and UDP" "off") || return

            local output
            if [[ "$proto" == "both" ]]; then
                output=$(ufw allow "$port" 2>&1)
            else
                output=$(ufw allow "$port/$proto" 2>&1)
            fi

            if [[ $? -eq 0 ]]; then
                log_info "Added UFW rule: allow $port/$proto"
                ui_msgbox "Success" "Rule added:\n$output"
            else
                ui_msgbox "Error" "Failed to add rule:\n$output"
            fi
            ;;

        service)
            local service
            service=$(ui_inputbox "Allow Service" "Enter service name (e.g., ssh, http, https):") || return

            local output
            output=$(ufw allow "$service" 2>&1)

            if [[ $? -eq 0 ]]; then
                log_info "Added UFW rule: allow $service"
                ui_msgbox "Success" "Rule added:\n$output"
            else
                ui_msgbox "Error" "Failed to add rule:\n$output"
            fi
            ;;

        ip)
            local ip
            ip=$(ui_inputbox "Allow IP" "Enter IP address (e.g., 192.168.1.100):") || return

            if ! validate_ip "$ip"; then
                ui_msgbox "Error" "Invalid IP address"
                return 1
            fi

            local output
            output=$(ufw allow from "$ip" 2>&1)

            if [[ $? -eq 0 ]]; then
                log_info "Added UFW rule: allow from $ip"
                ui_msgbox "Success" "Rule added:\n$output"
            else
                ui_msgbox "Error" "Failed to add rule:\n$output"
            fi
            ;;

        subnet)
            local subnet
            subnet=$(ui_inputbox "Allow Subnet" "Enter subnet (e.g., 192.168.1.0/24):") || return

            local output
            output=$(ufw allow from "$subnet" 2>&1)

            if [[ $? -eq 0 ]]; then
                log_info "Added UFW rule: allow from $subnet"
                ui_msgbox "Success" "Rule added:\n$output"
            else
                ui_msgbox "Error" "Failed to add rule:\n$output"
            fi
            ;;
    esac
}

# Add deny rule
add_deny_rule() {
    if ! require_root; then
        return 1
    fi

    if ! check_ufw_installed; then
        return 1
    fi

    local rule_type
    rule_type=$(ui_menu "Add Deny Rule" "Select rule type:" \
        "port" "Deny specific port" \
        "ip" "Deny from IP address" \
        "subnet" "Deny from subnet") || return

    case "$rule_type" in
        port)
            local port
            port=$(ui_inputbox "Deny Port" "Enter port number:") || return

            if ! validate_port "$port"; then
                ui_msgbox "Error" "Invalid port number"
                return 1
            fi

            local proto
            proto=$(ui_radiolist "Protocol" "Select protocol:" \
                "tcp" "TCP" "on" \
                "udp" "UDP" "off" \
                "both" "TCP and UDP" "off") || return

            local output
            if [[ "$proto" == "both" ]]; then
                output=$(ufw deny "$port" 2>&1)
            else
                output=$(ufw deny "$port/$proto" 2>&1)
            fi

            if [[ $? -eq 0 ]]; then
                log_info "Added UFW rule: deny $port/$proto"
                ui_msgbox "Success" "Rule added:\n$output"
            else
                ui_msgbox "Error" "Failed to add rule:\n$output"
            fi
            ;;

        ip)
            local ip
            ip=$(ui_inputbox "Deny IP" "Enter IP address:") || return

            if ! validate_ip "$ip"; then
                ui_msgbox "Error" "Invalid IP address"
                return 1
            fi

            local output
            output=$(ufw deny from "$ip" 2>&1)

            if [[ $? -eq 0 ]]; then
                log_info "Added UFW rule: deny from $ip"
                ui_msgbox "Success" "Rule added:\n$output"
            else
                ui_msgbox "Error" "Failed to add rule:\n$output"
            fi
            ;;

        subnet)
            local subnet
            subnet=$(ui_inputbox "Deny Subnet" "Enter subnet (e.g., 10.0.0.0/8):") || return

            local output
            output=$(ufw deny from "$subnet" 2>&1)

            if [[ $? -eq 0 ]]; then
                log_info "Added UFW rule: deny from $subnet"
                ui_msgbox "Success" "Rule added:\n$output"
            else
                ui_msgbox "Error" "Failed to add rule:\n$output"
            fi
            ;;
    esac
}

# Delete rule
delete_rule() {
    if ! require_root; then
        return 1
    fi

    if ! check_ufw_installed; then
        return 1
    fi

    # Get numbered rules
    local rules
    rules=$(ufw status numbered 2>&1)

    if [[ "$rules" == *"Status: inactive"* ]]; then
        ui_msgbox "Info" "UFW is inactive. No rules to delete."
        return
    fi

    echo "$rules" > /tmp/ufw_rules.txt
    ui_textbox "Current Rules" /tmp/ufw_rules.txt
    rm -f /tmp/ufw_rules.txt

    local rule_num
    rule_num=$(ui_inputbox "Delete Rule" "Enter rule number to delete:") || return

    if [[ ! "$rule_num" =~ ^[0-9]+$ ]]; then
        ui_msgbox "Error" "Invalid rule number"
        return 1
    fi

    if ui_yesno "Confirm Delete" "Are you sure you want to delete rule $rule_num?"; then
        local output
        output=$(yes | ufw delete "$rule_num" 2>&1)

        if [[ $? -eq 0 ]]; then
            log_info "Deleted UFW rule $rule_num"
            ui_msgbox "Success" "Rule deleted:\n$output"
        else
            ui_msgbox "Error" "Failed to delete rule:\n$output"
        fi
    fi
}

# Reset UFW
reset_ufw() {
    if ! require_root; then
        return 1
    fi

    if ! check_ufw_installed; then
        return 1
    fi

    if ui_yesno "Reset UFW" "WARNING: This will reset all UFW rules to defaults!\n\nAre you sure you want to continue?"; then
        if ui_yesno "Confirm Reset" "This action cannot be undone.\n\nAre you absolutely sure?"; then
            local output
            output=$(yes | ufw reset 2>&1)

            if [[ $? -eq 0 ]]; then
                log_info "UFW reset to defaults"
                ui_msgbox "Success" "UFW has been reset to defaults.\n\nNote: UFW is now disabled."
            else
                ui_msgbox "Error" "Failed to reset UFW:\n$output"
            fi
        fi
    fi
}

# Set default policies
set_defaults() {
    if ! require_root; then
        return 1
    fi

    if ! check_ufw_installed; then
        return 1
    fi

    local incoming
    incoming=$(ui_radiolist "Default Incoming" "Select default policy for incoming traffic:" \
        "deny" "Deny (recommended)" "on" \
        "allow" "Allow" "off" \
        "reject" "Reject" "off") || return

    local outgoing
    outgoing=$(ui_radiolist "Default Outgoing" "Select default policy for outgoing traffic:" \
        "allow" "Allow (recommended)" "on" \
        "deny" "Deny" "off" \
        "reject" "Reject" "off") || return

    local output=""
    output+=$(ufw default "$incoming" incoming 2>&1)
    output+="\n"
    output+=$(ufw default "$outgoing" outgoing 2>&1)

    log_info "Set UFW defaults: incoming=$incoming, outgoing=$outgoing"
    ui_msgbox "Success" "Default policies set:\n\n$output"
}

# Quick setup for common services
quick_setup() {
    if ! require_root; then
        return 1
    fi

    if ! check_ufw_installed; then
        return 1
    fi

    local services
    services=$(ui_checklist "Quick Setup" "Select services to allow:" \
        "ssh" "SSH (port 22)" "on" \
        "http" "HTTP (port 80)" "off" \
        "https" "HTTPS (port 443)" "off" \
        "mysql" "MySQL (port 3306)" "off" \
        "postgresql" "PostgreSQL (port 5432)" "off" \
        "ftp" "FTP (port 21)" "off" \
        "smtp" "SMTP (port 25)" "off" \
        "dns" "DNS (port 53)" "off") || return

    if [[ -z "$services" ]]; then
        ui_msgbox "Info" "No services selected"
        return
    fi

    local output=""
    for service in $services; do
        service=$(echo "$service" | tr -d '"')
        local result
        result=$(ufw allow "$service" 2>&1)
        output+="$service: $result\n"
        log_info "Added UFW rule: allow $service"
    done

    ui_msgbox "Success" "Rules added:\n\n$output"
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "UFW Manager" "Select operation:" \
            "install" "Install UFW" \
            "status" "Show UFW status" \
            "enable" "Enable UFW" \
            "disable" "Disable UFW" \
            "allow" "Add allow rule" \
            "deny" "Add deny rule" \
            "delete" "Delete rule" \
            "defaults" "Set default policies" \
            "quick" "Quick setup (common services)" \
            "reset" "Reset UFW to defaults") || break

        case "$choice" in
            install)  install_ufw ;;
            status)   show_status ;;
            enable)   enable_ufw ;;
            disable)  disable_ufw ;;
            allow)    add_allow_rule ;;
            deny)     add_deny_rule ;;
            delete)   delete_rule ;;
            defaults) set_defaults ;;
            quick)    quick_setup ;;
            reset)    reset_ufw ;;
        esac
    done
}
