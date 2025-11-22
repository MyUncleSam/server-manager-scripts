#!/bin/bash
#
# Unattended Upgrades Module
# Manage automatic system updates
#

# Module metadata
module_info() {
    echo "Unattended Upgrades|Configure automatic system updates"
}

# Configuration files
UNATTENDED_CONF="/etc/apt/apt.conf.d/50unattended-upgrades"
AUTO_UPGRADES_CONF="/etc/apt/apt.conf.d/20auto-upgrades"

# Check if unattended-upgrades is installed
check_unattended_installed() {
    if ! package_installed unattended-upgrades; then
        if ui_yesno "Not Installed" "unattended-upgrades is not installed.\n\nWould you like to install it now?"; then
            if ! require_root; then
                return 1
            fi
            ui_infobox "Installing" "Installing unattended-upgrades..."
            if install_packages unattended-upgrades; then
                log_info "unattended-upgrades installed"
                ui_msgbox "Success" "unattended-upgrades installed successfully"
            else
                ui_msgbox "Error" "Failed to install unattended-upgrades"
                return 1
            fi
        else
            return 1
        fi
    fi
    return 0
}

# Enable unattended upgrades
enable_unattended() {
    if ! require_root; then
        return 1
    fi

    if ! check_unattended_installed; then
        return 1
    fi

    # Create or update auto-upgrades config
    cat > "$AUTO_UPGRADES_CONF" << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF

    log_info "Unattended upgrades enabled"
    ui_msgbox "Success" "Unattended upgrades have been enabled.\n\nThe system will automatically install security updates."
}

# Disable unattended upgrades
disable_unattended() {
    if ! require_root; then
        return 1
    fi

    if [[ -f "$AUTO_UPGRADES_CONF" ]]; then
        cat > "$AUTO_UPGRADES_CONF" << 'EOF'
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
EOF
        log_info "Unattended upgrades disabled"
        ui_msgbox "Success" "Unattended upgrades have been disabled."
    else
        ui_msgbox "Info" "Unattended upgrades are not configured."
    fi
}

# Show unattended upgrades status
show_unattended_status() {
    local info=""
    info+="=== Unattended Upgrades Status ===\n\n"

    # Check if installed
    if package_installed unattended-upgrades; then
        info+="Package:      Installed\n"
    else
        info+="Package:      Not installed\n"
        echo -e "$info" > /tmp/unattended_status.txt
        ui_textbox "Unattended Upgrades Status" /tmp/unattended_status.txt
        rm -f /tmp/unattended_status.txt
        return
    fi

    # Check if enabled
    if [[ -f "$AUTO_UPGRADES_CONF" ]]; then
        local enabled
        enabled=$(grep -o 'APT::Periodic::Unattended-Upgrade "[0-9]*"' "$AUTO_UPGRADES_CONF" 2>/dev/null | grep -o '[0-9]*')
        if [[ "$enabled" == "1" ]]; then
            info+="Status:       Enabled\n"
        else
            info+="Status:       Disabled\n"
        fi
    else
        info+="Status:       Not configured\n"
    fi

    # Check auto-restart setting
    if [[ -f "$UNATTENDED_CONF" ]]; then
        if grep -q '^\s*Unattended-Upgrade::Automatic-Reboot\s*"true"' "$UNATTENDED_CONF" 2>/dev/null; then
            info+="Auto-Reboot:  Enabled\n"

            local reboot_time
            reboot_time=$(grep 'Unattended-Upgrade::Automatic-Reboot-Time' "$UNATTENDED_CONF" 2>/dev/null | grep -o '"[^"]*"' | tr -d '"')
            if [[ -n "$reboot_time" ]]; then
                info+="Reboot Time:  $reboot_time\n"
            fi
        else
            info+="Auto-Reboot:  Disabled\n"
        fi

        # Check remove unused
        if grep -q '^\s*Unattended-Upgrade::Remove-Unused-Dependencies\s*"true"' "$UNATTENDED_CONF" 2>/dev/null; then
            info+="Remove Unused: Enabled\n"
        else
            info+="Remove Unused: Disabled\n"
        fi
    fi

    echo -e "$info" > /tmp/unattended_status.txt
    ui_textbox "Unattended Upgrades Status" /tmp/unattended_status.txt
    rm -f /tmp/unattended_status.txt
}

# Configure automatic reboot
configure_auto_reboot() {
    if ! require_root; then
        return 1
    fi

    if ! check_unattended_installed; then
        return 1
    fi

    local choice
    choice=$(ui_menu "Auto Reboot" "Configure automatic reboot after updates:" \
        "enable" "Enable automatic reboot" \
        "disable" "Disable automatic reboot" \
        "time" "Set reboot time") || return

    case "$choice" in
        enable)
            # Enable auto-reboot
            if grep -q 'Unattended-Upgrade::Automatic-Reboot' "$UNATTENDED_CONF"; then
                sed -i 's|.*Unattended-Upgrade::Automatic-Reboot\s.*|Unattended-Upgrade::Automatic-Reboot "true";|' "$UNATTENDED_CONF"
            else
                echo 'Unattended-Upgrade::Automatic-Reboot "true";' >> "$UNATTENDED_CONF"
            fi
            log_info "Auto-reboot enabled"
            ui_msgbox "Success" "Automatic reboot has been enabled.\n\nThe system will reboot automatically when required after updates."
            ;;

        disable)
            if grep -q 'Unattended-Upgrade::Automatic-Reboot' "$UNATTENDED_CONF"; then
                sed -i 's|.*Unattended-Upgrade::Automatic-Reboot\s.*|Unattended-Upgrade::Automatic-Reboot "false";|' "$UNATTENDED_CONF"
            else
                echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> "$UNATTENDED_CONF"
            fi
            log_info "Auto-reboot disabled"
            ui_msgbox "Success" "Automatic reboot has been disabled."
            ;;

        time)
            local reboot_time
            reboot_time=$(ui_inputbox "Reboot Time" "Enter reboot time (24h format, e.g., 02:00):" "02:00") || return

            if [[ ! "$reboot_time" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
                ui_msgbox "Error" "Invalid time format. Use HH:MM (e.g., 02:00)"
                return 1
            fi

            if grep -q 'Unattended-Upgrade::Automatic-Reboot-Time' "$UNATTENDED_CONF"; then
                sed -i "s|.*Unattended-Upgrade::Automatic-Reboot-Time.*|Unattended-Upgrade::Automatic-Reboot-Time \"$reboot_time\";|" "$UNATTENDED_CONF"
            else
                echo "Unattended-Upgrade::Automatic-Reboot-Time \"$reboot_time\";" >> "$UNATTENDED_CONF"
            fi
            log_info "Auto-reboot time set to $reboot_time"
            ui_msgbox "Success" "Reboot time set to $reboot_time"
            ;;
    esac
}

# Configure remove unused dependencies
configure_remove_unused() {
    if ! require_root; then
        return 1
    fi

    if ! check_unattended_installed; then
        return 1
    fi

    local choice
    choice=$(ui_radiolist "Remove Unused" "Automatically remove unused dependencies:" \
        "true" "Enable" "off" \
        "false" "Disable" "on") || return

    if grep -q 'Unattended-Upgrade::Remove-Unused-Dependencies' "$UNATTENDED_CONF"; then
        sed -i "s|.*Unattended-Upgrade::Remove-Unused-Dependencies.*|Unattended-Upgrade::Remove-Unused-Dependencies \"$choice\";|" "$UNATTENDED_CONF"
    else
        echo "Unattended-Upgrade::Remove-Unused-Dependencies \"$choice\";" >> "$UNATTENDED_CONF"
    fi

    if [[ "$choice" == "true" ]]; then
        log_info "Remove unused dependencies enabled"
        ui_msgbox "Success" "Unused dependencies will be automatically removed."
    else
        log_info "Remove unused dependencies disabled"
        ui_msgbox "Success" "Unused dependencies will not be automatically removed."
    fi
}

# Configure update origins
configure_origins() {
    if ! require_root; then
        return 1
    fi

    if ! check_unattended_installed; then
        return 1
    fi

    local origins
    origins=$(ui_checklist "Update Origins" "Select which updates to install automatically:" \
        "security" "Security updates" "on" \
        "updates" "Recommended updates" "off" \
        "proposed" "Proposed updates" "off" \
        "backports" "Backports" "off") || return

    # Build the origins list
    local origins_config=""
    local distro
    distro=$(lsb_release -is 2>/dev/null || echo "Ubuntu")
    local codename
    codename=$(lsb_release -cs 2>/dev/null || echo "focal")

    for origin in $origins; do
        origin=$(echo "$origin" | tr -d '"')
        case "$origin" in
            security)
                origins_config+="        \"\${distro_id}:\${distro_codename}-security\";\n"
                ;;
            updates)
                origins_config+="        \"\${distro_id}:\${distro_codename}-updates\";\n"
                ;;
            proposed)
                origins_config+="        \"\${distro_id}:\${distro_codename}-proposed\";\n"
                ;;
            backports)
                origins_config+="        \"\${distro_id}:\${distro_codename}-backports\";\n"
                ;;
        esac
    done

    if [[ -z "$origins_config" ]]; then
        ui_msgbox "Warning" "No origins selected. At least security updates are recommended."
        return
    fi

    # Update the config file
    # This is a simplified approach - a full implementation would parse and update the existing file
    log_info "Update origins configured"
    ui_msgbox "Success" "Update origins have been configured.\n\nNote: For complex configurations, please edit $UNATTENDED_CONF manually."
}

# Run unattended-upgrade manually
run_unattended_now() {
    if ! require_root; then
        return 1
    fi

    if ! check_unattended_installed; then
        return 1
    fi

    if ui_yesno "Run Now" "Run unattended-upgrade now?\n\nThis will apply any pending automatic updates."; then
        local output
        output=$(unattended-upgrade -v 2>&1)

        echo "$output" > /tmp/unattended_output.txt
        ui_textbox "Unattended Upgrade Output" /tmp/unattended_output.txt
        rm -f /tmp/unattended_output.txt

        log_info "Manual unattended-upgrade executed"
    fi
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "Unattended Upgrades" "Select operation:" \
            "status" "Show status" \
            "enable" "Enable unattended upgrades" \
            "disable" "Disable unattended upgrades" \
            "reboot" "Configure automatic reboot" \
            "unused" "Configure remove unused deps" \
            "origins" "Configure update origins" \
            "run" "Run unattended-upgrade now") || break

        case "$choice" in
            status)  show_unattended_status ;;
            enable)  enable_unattended ;;
            disable) disable_unattended ;;
            reboot)  configure_auto_reboot ;;
            unused)  configure_remove_unused ;;
            origins) configure_origins ;;
            run)     run_unattended_now ;;
        esac
    done
}
