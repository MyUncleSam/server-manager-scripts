#!/bin/bash
#
# CrowdSec Module
# Install, configure, and manage CrowdSec IDS/IPS
#

# Module metadata
module_info() {
    echo "CrowdSec|Install and manage CrowdSec IDS/IPS"
}

# Configuration paths
CROWDSEC_CONFIG="/etc/crowdsec/config.yaml"
CROWDSEC_LOCAL_API="/etc/crowdsec/local_api_credentials.yaml"
CROWDSEC_ACQUIS="/etc/crowdsec/acquis.yaml"
CROWDSEC_LOG="/var/log/crowdsec.log"
CSCLI="/usr/bin/cscli"

# Check if CrowdSec is installed
is_crowdsec_installed() {
    command_exists cscli && command_exists crowdsec
}

# Check if CrowdSec service is running
is_crowdsec_running() {
    service_is_running crowdsec
}

# Get CrowdSec version
get_crowdsec_version() {
    if is_crowdsec_installed; then
        cscli version 2>/dev/null | head -1
    else
        echo "Not installed"
    fi
}

# Install CrowdSec
install_crowdsec() {
    if is_crowdsec_installed; then
        ui_msgbox "Info" "CrowdSec is already installed"
        return 0
    fi

    if ! require_root; then
        return 1
    fi

    if ! ui_yesno "Install CrowdSec" "Would you like to install CrowdSec IDS/IPS?\n\nThis will:\n• Add CrowdSec repository\n• Install crowdsec package\n• Enable and start the service"; then
        return
    fi

    # Show progress
    (
        echo 10
        echo "# Adding CrowdSec repository..."

        # Add repository
        if ! curl -fsSL https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh 2>/dev/null | bash >/dev/null 2>&1; then
            echo "ERROR: Failed to add repository"
            exit 1
        fi

        echo 40
        echo "# Installing CrowdSec package..."

        # Update package list
        apt-get update >/dev/null 2>&1

        echo 60
        echo "# Installing crowdsec..."

        # Install package
        if ! apt-get install -y crowdsec >/dev/null 2>&1; then
            echo "ERROR: Failed to install package"
            exit 1
        fi

        echo 80
        echo "# Enabling and starting service..."

        # Enable and start service
        systemctl enable crowdsec >/dev/null 2>&1
        systemctl start crowdsec >/dev/null 2>&1

        echo 100
        echo "# Installation complete"

    ) | ui_gauge "Installing CrowdSec" "Please wait..." 20

    if is_crowdsec_installed; then
        log_info "CrowdSec installed and started"
        ui_msgbox "Success" "CrowdSec installed successfully.\n\nService is now running."

        # Offer Quick Setup
        if ui_yesno "Quick Setup" "Would you like to run Quick Setup to install common protection collections and configure firewall bouncer?"; then
            quick_setup
        fi
    else
        ui_msgbox "Error" "Failed to install CrowdSec"
        return 1
    fi
}

# Uninstall CrowdSec
uninstall_crowdsec() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Info" "CrowdSec is not installed"
        return 0
    fi

    if ! require_root; then
        return 1
    fi

    if ! ui_yesno "Uninstall CrowdSec" "Are you sure you want to uninstall CrowdSec?\n\nThis will:\n• Stop the service\n• Remove the package\n• Optionally remove configuration"; then
        return
    fi

    local purge_config="no"
    if ui_yesno "Remove Configuration" "Remove all CrowdSec configuration files too?\n\nThis includes scenarios, collections, decisions, and settings."; then
        purge_config="yes"
    fi

    ui_infobox "Uninstalling" "Removing CrowdSec..."

    # Stop service
    systemctl stop crowdsec 2>/dev/null
    systemctl disable crowdsec 2>/dev/null

    # Remove package
    if [[ "$purge_config" == "yes" ]]; then
        apt-get purge -y crowdsec crowdsec-firewall-bouncer-iptables >/dev/null 2>&1
        rm -rf /etc/crowdsec
    else
        apt-get remove -y crowdsec >/dev/null 2>&1
    fi

    log_info "CrowdSec uninstalled"
    ui_msgbox "Success" "CrowdSec has been uninstalled"
}

# Show CrowdSec status
show_status() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    local info=""
    info+="=== CrowdSec Status ===\n\n"

    # Service status
    if is_crowdsec_running; then
        info+="Service:              Running ✓\n"
    else
        info+="Service:              Stopped ✗\n"
    fi

    # Version
    local version
    version=$(cscli version 2>/dev/null | head -1 | awk '{print $NF}')
    info+="Version:              $version\n\n"

    # Scenarios count
    local scenarios_count
    scenarios_count=$(cscli scenarios list -o raw 2>/dev/null | wc -l)
    info+="Installed Scenarios:  $scenarios_count\n"

    # Collections count
    local collections_count
    collections_count=$(cscli collections list -o raw 2>/dev/null | wc -l)
    info+="Installed Collections: $collections_count\n"

    # Active decisions (bans)
    local decisions_count
    decisions_count=$(cscli decisions list -o raw 2>/dev/null | wc -l)
    info+="Active Decisions:     $decisions_count\n"

    # Bouncers count
    local bouncers_count
    bouncers_count=$(cscli bouncers list -o raw 2>/dev/null | wc -l)
    info+="Registered Bouncers:  $bouncers_count\n\n"

    # Hub status
    info+="=== Hub Status ===\n\n"
    local hub_info
    hub_info=$(cscli hub list 2>/dev/null | grep -E "PARSERS|SCENARIOS|COLLECTIONS|POSTOVERFLOWS" | head -10)
    info+="$hub_info\n"

    echo -e "$info" > /tmp/crowdsec_status.txt
    ui_textbox "CrowdSec Status" /tmp/crowdsec_status.txt
    rm -f /tmp/crowdsec_status.txt
}

# Show active decisions (bans)
show_decisions() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    local decisions
    decisions=$(cscli decisions list 2>/dev/null)

    if [[ -z "$decisions" || $(echo "$decisions" | wc -l) -le 1 ]]; then
        ui_msgbox "Info" "No active decisions (bans) found"
        return
    fi

    local info=""
    info+="=== Active Decisions ===\n\n"
    info+="$decisions\n"

    echo -e "$info" > /tmp/crowdsec_decisions.txt
    ui_textbox "Active Decisions" /tmp/crowdsec_decisions.txt
    rm -f /tmp/crowdsec_decisions.txt
}

# Service control submenu
service_control() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    if ! require_root; then
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Service Control" "Select operation:" \
            "start" "Start CrowdSec service" \
            "stop" "Stop CrowdSec service" \
            "restart" "Restart CrowdSec service" \
            "reload" "Reload CrowdSec configuration" \
            "status" "Show systemd service status") || break

        case "$choice" in
            start)
                systemctl start crowdsec
                if is_crowdsec_running; then
                    log_info "CrowdSec service started"
                    ui_msgbox "Success" "CrowdSec service started"
                else
                    ui_msgbox "Error" "Failed to start CrowdSec service"
                fi
                ;;
            stop)
                systemctl stop crowdsec
                log_info "CrowdSec service stopped"
                ui_msgbox "Success" "CrowdSec service stopped"
                ;;
            restart)
                systemctl restart crowdsec
                if is_crowdsec_running; then
                    log_info "CrowdSec service restarted"
                    ui_msgbox "Success" "CrowdSec service restarted"
                else
                    ui_msgbox "Error" "Failed to restart CrowdSec service"
                fi
                ;;
            reload)
                systemctl reload crowdsec
                log_info "CrowdSec configuration reloaded"
                ui_msgbox "Success" "CrowdSec configuration reloaded"
                ;;
            status)
                local status_output
                status_output=$(systemctl status crowdsec 2>&1)
                echo "$status_output" > /tmp/crowdsec_systemd_status.txt
                ui_textbox "Service Status" /tmp/crowdsec_systemd_status.txt
                rm -f /tmp/crowdsec_systemd_status.txt
                ;;
        esac
    done
}

# View logs
view_logs() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    local choice
    choice=$(ui_menu "View Logs" "Select log to view:" \
        "crowdsec" "CrowdSec service log (journalctl)" \
        "decisions" "Decision logs" \
        "file" "Log file (/var/log/crowdsec.log)") || return

    case "$choice" in
        crowdsec)
            local log_output
            log_output=$(journalctl -u crowdsec -n 100 --no-pager 2>&1)
            echo "$log_output" > /tmp/crowdsec_journal.txt
            ui_textbox "CrowdSec Log (last 100 lines)" /tmp/crowdsec_journal.txt
            rm -f /tmp/crowdsec_journal.txt
            ;;
        decisions)
            local decisions_log
            decisions_log=$(cscli decisions list -o raw 2>&1)
            echo "$decisions_log" > /tmp/crowdsec_decisions_log.txt
            ui_textbox "Decision Logs" /tmp/crowdsec_decisions_log.txt
            rm -f /tmp/crowdsec_decisions_log.txt
            ;;
        file)
            if [[ -f "$CROWDSEC_LOG" ]]; then
                tail -100 "$CROWDSEC_LOG" > /tmp/crowdsec_file_log.txt
                ui_textbox "CrowdSec Log File (last 100 lines)" /tmp/crowdsec_file_log.txt
                rm -f /tmp/crowdsec_file_log.txt
            else
                ui_msgbox "Info" "Log file not found: $CROWDSEC_LOG"
            fi
            ;;
    esac
}

# Ban IP manually
ban_ip() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    if ! require_root; then
        return 1
    fi

    # Get IP address
    local ip
    ip=$(ui_inputbox "Ban IP" "Enter IP address to ban:") || return

    if ! validate_ip "$ip"; then
        ui_msgbox "Error" "Invalid IP address format"
        return 1
    fi

    # Get duration
    local duration
    duration=$(ui_inputbox "Ban Duration" "Enter ban duration:\n\nExamples:\n• 4h (4 hours)\n• 2d (2 days)\n• 1w (1 week)\n• 0 (permanent)" "4h") || return

    # Get reason
    local reason
    reason=$(ui_inputbox "Ban Reason" "Enter reason for ban (optional):" "Manual ban") || reason="Manual ban"

    # Get ban type
    local ban_type
    ban_type=$(ui_radiolist "Ban Type" "Select action type:" \
        "ban" "Ban (block completely)" "on" \
        "captcha" "Captcha challenge" "off" \
        "throttle" "Throttle (rate limit)" "off") || ban_type="ban"

    # Confirm
    if ! ui_yesno "Confirm Ban" "Ban IP: $ip\nDuration: $duration\nType: $ban_type\nReason: $reason\n\nProceed?"; then
        return
    fi

    # Add decision
    if cscli decisions add --ip "$ip" --duration "$duration" --type "$ban_type" --reason "$reason" 2>&1; then
        log_info "Banned IP: $ip (duration: $duration, type: $ban_type)"
        ui_msgbox "Success" "IP $ip has been banned\n\nDuration: $duration\nType: $ban_type"
    else
        ui_msgbox "Error" "Failed to ban IP"
    fi
}

# Unban IP
unban_ip() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    if ! require_root; then
        return 1
    fi

    # Get IP address
    local ip
    ip=$(ui_inputbox "Unban IP" "Enter IP address to unban:") || return

    if ! validate_ip "$ip"; then
        ui_msgbox "Error" "Invalid IP address format"
        return 1
    fi

    # Check if IP is currently banned
    local decision_info
    decision_info=$(cscli decisions list --ip "$ip" 2>/dev/null)

    if [[ -z "$decision_info" || $(echo "$decision_info" | wc -l) -le 1 ]]; then
        ui_msgbox "Info" "No active decisions found for IP: $ip"
        return
    fi

    # Show current decision
    ui_msgbox "Current Decision" "$decision_info"

    # Confirm removal
    if ! ui_yesno "Confirm Unban" "Remove ban for IP: $ip?"; then
        return
    fi

    # Remove decision
    if cscli decisions delete --ip "$ip" 2>&1; then
        log_info "Unbanned IP: $ip"
        ui_msgbox "Success" "IP $ip has been unbanned"
    else
        ui_msgbox "Error" "Failed to unban IP"
    fi
}

# Clear all decisions
clear_all_decisions() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    if ! require_root; then
        return 1
    fi

    # Count active decisions
    local count
    count=$(cscli decisions list -o raw 2>/dev/null | wc -l)

    if [[ "$count" -eq 0 ]]; then
        ui_msgbox "Info" "No active decisions to clear"
        return
    fi

    # Confirm
    if ! ui_yesno "Confirm Clear All" "This will remove ALL $count active decisions (bans).\n\nAre you sure?"; then
        return
    fi

    # Clear all decisions
    if cscli decisions delete --all 2>&1; then
        log_info "Cleared all CrowdSec decisions"
        ui_msgbox "Success" "All decisions have been cleared"
    else
        ui_msgbox "Error" "Failed to clear decisions"
    fi
}

# Manage whitelist
manage_whitelist() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Manage Whitelist" "Select operation:" \
            "show" "Show whitelisted IPs" \
            "add" "Add IP to whitelist" \
            "remove" "Remove IP from whitelist") || break

        case "$choice" in
            show)
                local whitelist
                whitelist=$(cscli decisions list --type whitelist 2>/dev/null)

                if [[ -z "$whitelist" || $(echo "$whitelist" | wc -l) -le 1 ]]; then
                    ui_msgbox "Info" "No whitelisted IPs found"
                else
                    echo "$whitelist" > /tmp/crowdsec_whitelist.txt
                    ui_textbox "Whitelisted IPs" /tmp/crowdsec_whitelist.txt
                    rm -f /tmp/crowdsec_whitelist.txt
                fi
                ;;
            add)
                if ! require_root; then
                    continue
                fi

                local ip
                ip=$(ui_inputbox "Add to Whitelist" "Enter IP address to whitelist:") || continue

                if ! validate_ip "$ip"; then
                    ui_msgbox "Error" "Invalid IP address format"
                    continue
                fi

                local reason
                reason=$(ui_inputbox "Whitelist Reason" "Enter reason (optional):" "Whitelisted IP") || reason="Whitelisted IP"

                if cscli decisions add --ip "$ip" --type whitelist --reason "$reason" 2>&1; then
                    log_info "Whitelisted IP: $ip"
                    ui_msgbox "Success" "IP $ip added to whitelist"
                else
                    ui_msgbox "Error" "Failed to add IP to whitelist"
                fi
                ;;
            remove)
                if ! require_root; then
                    continue
                fi

                local ip
                ip=$(ui_inputbox "Remove from Whitelist" "Enter IP address to remove from whitelist:") || continue

                if cscli decisions delete --ip "$ip" --type whitelist 2>&1; then
                    log_info "Removed IP from whitelist: $ip"
                    ui_msgbox "Success" "IP $ip removed from whitelist"
                else
                    ui_msgbox "Error" "Failed to remove IP from whitelist"
                fi
                ;;
        esac
    done
}

# Show installed scenarios
show_scenarios() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    local scenarios
    scenarios=$(cscli scenarios list 2>/dev/null)

    if [[ -z "$scenarios" ]]; then
        ui_msgbox "Info" "No scenarios found"
        return
    fi

    echo "$scenarios" > /tmp/crowdsec_scenarios.txt
    ui_textbox "Installed Scenarios" /tmp/crowdsec_scenarios.txt
    rm -f /tmp/crowdsec_scenarios.txt
}

# Manage collections
manage_collections() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Manage Collections" "Select operation:" \
            "list" "List installed collections" \
            "install" "Install collection from hub" \
            "remove" "Remove collection" \
            "update" "Update hub index" \
            "upgrade" "Upgrade installed items") || break

        case "$choice" in
            list)
                local collections
                collections=$(cscli collections list 2>/dev/null)

                if [[ -z "$collections" ]]; then
                    ui_msgbox "Info" "No collections found"
                else
                    echo "$collections" > /tmp/crowdsec_collections.txt
                    ui_textbox "Installed Collections" /tmp/crowdsec_collections.txt
                    rm -f /tmp/crowdsec_collections.txt
                fi
                ;;
            install)
                if ! require_root; then
                    continue
                fi

                local collection
                collection=$(ui_inputbox "Install Collection" "Enter collection name:\n\nPopular collections:\n• crowdsecurity/linux\n• crowdsecurity/sshd\n• crowdsecurity/http-cve\n• crowdsecurity/nginx\n• crowdsecurity/apache2" "crowdsecurity/") || continue

                if [[ -z "$collection" ]]; then
                    continue
                fi

                ui_infobox "Installing" "Installing collection: $collection..."

                if cscli collections install "$collection" 2>&1 && systemctl reload crowdsec; then
                    log_info "Installed collection: $collection"
                    ui_msgbox "Success" "Collection installed: $collection\n\nCrowdSec has been reloaded."
                else
                    ui_msgbox "Error" "Failed to install collection"
                fi
                ;;
            remove)
                if ! require_root; then
                    continue
                fi

                local collection
                collection=$(ui_inputbox "Remove Collection" "Enter collection name to remove:") || continue

                if [[ -z "$collection" ]]; then
                    continue
                fi

                if ! ui_yesno "Confirm" "Remove collection: $collection?"; then
                    continue
                fi

                if cscli collections remove "$collection" 2>&1 && systemctl reload crowdsec; then
                    log_info "Removed collection: $collection"
                    ui_msgbox "Success" "Collection removed: $collection"
                else
                    ui_msgbox "Error" "Failed to remove collection"
                fi
                ;;
            update)
                if ! require_root; then
                    continue
                fi

                ui_infobox "Updating" "Updating CrowdSec hub index..."

                if cscli hub update 2>&1; then
                    ui_msgbox "Success" "Hub index updated successfully"
                else
                    ui_msgbox "Error" "Failed to update hub index"
                fi
                ;;
            upgrade)
                if ! require_root; then
                    continue
                fi

                if ! ui_yesno "Upgrade All" "Upgrade all installed scenarios, collections, and parsers from hub?"; then
                    continue
                fi

                ui_infobox "Upgrading" "Upgrading all items from hub..."

                if cscli hub upgrade 2>&1 && systemctl reload crowdsec; then
                    log_info "Upgraded CrowdSec hub items"
                    ui_msgbox "Success" "All items upgraded successfully"
                else
                    ui_msgbox "Error" "Failed to upgrade items"
                fi
                ;;
        esac
    done
}

# Quick Setup
quick_setup() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed.\n\nPlease install CrowdSec first."
        return 1
    fi

    if ! require_root; then
        return 1
    fi

    # Select collections
    local collections
    collections=$(ui_checklist "Quick Setup - Collections" "Select protection collections to install:" \
        "crowdsecurity/linux" "Base Linux protection (recommended)" "on" \
        "crowdsecurity/sshd" "SSH brute force protection (recommended)" "on" \
        "crowdsecurity/http-cve" "HTTP CVE exploits" "on" \
        "crowdsecurity/base-http-scenarios" "Base HTTP attack scenarios" "on" \
        "crowdsecurity/nginx" "Nginx web server protection" "off" \
        "crowdsecurity/apache2" "Apache web server protection" "off") || return

    # Ask about firewall bouncer
    local install_bouncer="no"
    if ui_yesno "Firewall Bouncer" "Install firewall bouncer to automatically block banned IPs with iptables?\n\nRecommended: Yes"; then
        install_bouncer="yes"
    fi

    # Show progress
    (
        echo 0
        echo "# Installing selected collections..."

        local progress=10
        for collection in $collections; do
            collection=$(echo "$collection" | tr -d '"')
            echo $progress
            echo "# Installing: $collection"
            cscli collections install "$collection" >/dev/null 2>&1
            progress=$((progress + 15))
        done

        echo 70
        echo "# Reloading CrowdSec..."
        systemctl reload crowdsec >/dev/null 2>&1

        if [[ "$install_bouncer" == "yes" ]]; then
            echo 80
            echo "# Installing firewall bouncer..."
            apt-get install -y crowdsec-firewall-bouncer-iptables >/dev/null 2>&1
            systemctl enable crowdsec-firewall-bouncer >/dev/null 2>&1
            systemctl start crowdsec-firewall-bouncer >/dev/null 2>&1
        fi

        echo 100
        echo "# Setup complete"

    ) | ui_gauge "Quick Setup" "Configuring CrowdSec..." 20

    log_info "CrowdSec quick setup completed"

    local summary="Quick setup completed!\n\nInstalled collections:\n"
    for collection in $collections; do
        collection=$(echo "$collection" | tr -d '"')
        summary+="• $collection\n"
    done

    if [[ "$install_bouncer" == "yes" ]]; then
        summary+="\nFirewall bouncer: Installed ✓"
    fi

    ui_msgbox "Setup Complete" "$summary"
}

# Manage bouncers
manage_bouncers() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Manage Bouncers" "Select operation:" \
            "list" "List registered bouncers" \
            "firewall" "Install firewall bouncer" \
            "add" "Register custom bouncer" \
            "remove" "Remove bouncer") || break

        case "$choice" in
            list)
                local bouncers
                bouncers=$(cscli bouncers list 2>/dev/null)

                if [[ -z "$bouncers" || $(echo "$bouncers" | wc -l) -le 1 ]]; then
                    ui_msgbox "Info" "No bouncers registered"
                else
                    echo "$bouncers" > /tmp/crowdsec_bouncers.txt
                    ui_textbox "Registered Bouncers" /tmp/crowdsec_bouncers.txt
                    rm -f /tmp/crowdsec_bouncers.txt
                fi
                ;;
            firewall)
                if ! require_root; then
                    continue
                fi

                # Check if already installed
                if command_exists crowdsec-firewall-bouncer; then
                    ui_msgbox "Info" "Firewall bouncer is already installed"
                    continue
                fi

                if ! ui_yesno "Install Firewall Bouncer" "Install CrowdSec firewall bouncer?\n\nThis will:\n• Install crowdsec-firewall-bouncer-iptables\n• Configure iptables integration\n• Automatically block banned IPs"; then
                    continue
                fi

                ui_infobox "Installing" "Installing firewall bouncer..."

                if apt-get install -y crowdsec-firewall-bouncer-iptables 2>&1 && \
                   systemctl enable crowdsec-firewall-bouncer 2>&1 && \
                   systemctl start crowdsec-firewall-bouncer 2>&1; then
                    log_info "Installed CrowdSec firewall bouncer"
                    ui_msgbox "Success" "Firewall bouncer installed and started.\n\nBanned IPs will now be automatically blocked by iptables."
                else
                    ui_msgbox "Error" "Failed to install firewall bouncer"
                fi
                ;;
            add)
                if ! require_root; then
                    continue
                fi

                local bouncer_name
                bouncer_name=$(ui_inputbox "Add Bouncer" "Enter bouncer name (alphanumeric and dashes only):") || continue

                if [[ -z "$bouncer_name" ]]; then
                    continue
                fi

                # Validate bouncer name
                if [[ ! "$bouncer_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    ui_msgbox "Error" "Invalid bouncer name. Use only alphanumeric characters, underscores, and dashes."
                    continue
                fi

                # Add bouncer and get API key
                local api_key
                api_key=$(cscli bouncers add "$bouncer_name" -o raw 2>&1 | tail -1)

                if [[ -n "$api_key" && "$api_key" != *"error"* ]]; then
                    log_info "Added bouncer: $bouncer_name"
                    ui_msgbox "Bouncer Added" "Bouncer registered: $bouncer_name\n\nAPI Key:\n$api_key\n\nSave this key - it won't be shown again!\n\nUse this key to configure your bouncer application."
                else
                    ui_msgbox "Error" "Failed to add bouncer"
                fi
                ;;
            remove)
                if ! require_root; then
                    continue
                fi

                local bouncer_name
                bouncer_name=$(ui_inputbox "Remove Bouncer" "Enter bouncer name to remove:") || continue

                if [[ -z "$bouncer_name" ]]; then
                    continue
                fi

                if ! ui_yesno "Confirm" "Remove bouncer: $bouncer_name?"; then
                    continue
                fi

                if cscli bouncers delete "$bouncer_name" 2>&1; then
                    log_info "Removed bouncer: $bouncer_name"
                    ui_msgbox "Success" "Bouncer removed: $bouncer_name"
                else
                    ui_msgbox "Error" "Failed to remove bouncer"
                fi
                ;;
        esac
    done
}

# Console enrollment
console_menu() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Console Management" "Select operation:" \
            "status" "Show console enrollment status" \
            "enroll" "Enroll to CrowdSec Console") || break

        case "$choice" in
            status)
                local console_status
                console_status=$(cscli console status 2>&1)
                echo "$console_status" > /tmp/crowdsec_console_status.txt
                ui_textbox "Console Status" /tmp/crowdsec_console_status.txt
                rm -f /tmp/crowdsec_console_status.txt
                ;;
            enroll)
                if ! require_root; then
                    continue
                fi

                local enrollment_key
                enrollment_key=$(ui_inputbox "Console Enrollment" "Enter your CrowdSec Console enrollment key:\n\n(Get this from https://app.crowdsec.net)") || continue

                if [[ -z "$enrollment_key" ]]; then
                    continue
                fi

                ui_infobox "Enrolling" "Enrolling to CrowdSec Console..."

                if cscli console enroll "$enrollment_key" 2>&1; then
                    log_info "Enrolled to CrowdSec Console"
                    ui_msgbox "Success" "Successfully enrolled to CrowdSec Console!\n\nYou can now manage this instance at:\nhttps://app.crowdsec.net"
                else
                    ui_msgbox "Error" "Failed to enroll to console.\n\nCheck that your enrollment key is valid."
                fi
                ;;
        esac
    done
}

# Manage parsers
manage_parsers() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Manage Parsers" "Select operation:" \
            "list" "List installed parsers" \
            "install" "Install parser from hub" \
            "remove" "Remove parser" \
            "upgrade" "Upgrade parsers") || break

        case "$choice" in
            list)
                local parsers
                parsers=$(cscli parsers list 2>/dev/null)

                if [[ -z "$parsers" ]]; then
                    ui_msgbox "Info" "No parsers found"
                else
                    echo "$parsers" > /tmp/crowdsec_parsers.txt
                    ui_textbox "Installed Parsers" /tmp/crowdsec_parsers.txt
                    rm -f /tmp/crowdsec_parsers.txt
                fi
                ;;
            install)
                if ! require_root; then
                    continue
                fi

                local parser
                parser=$(ui_inputbox "Install Parser" "Enter parser name from hub:") || continue

                if [[ -z "$parser" ]]; then
                    continue
                fi

                if cscli parsers install "$parser" 2>&1 && systemctl reload crowdsec; then
                    log_info "Installed parser: $parser"
                    ui_msgbox "Success" "Parser installed: $parser"
                else
                    ui_msgbox "Error" "Failed to install parser"
                fi
                ;;
            remove)
                if ! require_root; then
                    continue
                fi

                local parser
                parser=$(ui_inputbox "Remove Parser" "Enter parser name to remove:") || continue

                if [[ -z "$parser" ]]; then
                    continue
                fi

                if cscli parsers remove "$parser" 2>&1 && systemctl reload crowdsec; then
                    log_info "Removed parser: $parser"
                    ui_msgbox "Success" "Parser removed: $parser"
                else
                    ui_msgbox "Error" "Failed to remove parser"
                fi
                ;;
            upgrade)
                if ! require_root; then
                    continue
                fi

                if cscli parsers upgrade --all 2>&1 && systemctl reload crowdsec; then
                    ui_msgbox "Success" "All parsers upgraded"
                else
                    ui_msgbox "Error" "Failed to upgrade parsers"
                fi
                ;;
        esac
    done
}

# Manage postoverflows
manage_postoverflows() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Manage Postoverflows" "Select operation:" \
            "list" "List installed postoverflows" \
            "install" "Install postoverflow from hub" \
            "remove" "Remove postoverflow") || break

        case "$choice" in
            list)
                local postoverflows
                postoverflows=$(cscli postoverflows list 2>/dev/null)

                if [[ -z "$postoverflows" ]]; then
                    ui_msgbox "Info" "No postoverflows found"
                else
                    echo "$postoverflows" > /tmp/crowdsec_postoverflows.txt
                    ui_textbox "Installed Postoverflows" /tmp/crowdsec_postoverflows.txt
                    rm -f /tmp/crowdsec_postoverflows.txt
                fi
                ;;
            install)
                if ! require_root; then
                    continue
                fi

                local postoverflow
                postoverflow=$(ui_inputbox "Install Postoverflow" "Enter postoverflow name from hub:") || continue

                if [[ -z "$postoverflow" ]]; then
                    continue
                fi

                if cscli postoverflows install "$postoverflow" 2>&1 && systemctl reload crowdsec; then
                    log_info "Installed postoverflow: $postoverflow"
                    ui_msgbox "Success" "Postoverflow installed: $postoverflow"
                else
                    ui_msgbox "Error" "Failed to install postoverflow"
                fi
                ;;
            remove)
                if ! require_root; then
                    continue
                fi

                local postoverflow
                postoverflow=$(ui_inputbox "Remove Postoverflow" "Enter postoverflow name to remove:") || continue

                if [[ -z "$postoverflow" ]]; then
                    continue
                fi

                if cscli postoverflows remove "$postoverflow" 2>&1 && systemctl reload crowdsec; then
                    log_info "Removed postoverflow: $postoverflow"
                    ui_msgbox "Success" "Postoverflow removed: $postoverflow"
                else
                    ui_msgbox "Error" "Failed to remove postoverflow"
                fi
                ;;
        esac
    done
}

# Manage acquisition configuration
manage_acquisition() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Acquisition Configuration" "Select operation:" \
            "view" "View current acquisition config" \
            "edit" "Edit acquisition config manually" \
            "test" "Test configuration") || break

        case "$choice" in
            view)
                if [[ -f "$CROWDSEC_ACQUIS" ]]; then
                    ui_textbox "Acquisition Configuration" "$CROWDSEC_ACQUIS"
                else
                    ui_msgbox "Info" "Acquisition config file not found"
                fi
                ;;
            edit)
                if ! require_root; then
                    continue
                fi

                ui_msgbox "Edit Configuration" "The acquisition configuration file will open in your default editor.\n\nFile: $CROWDSEC_ACQUIS\n\nAfter editing, test the configuration before reloading CrowdSec."

                if command_exists nano; then
                    nano "$CROWDSEC_ACQUIS"
                elif command_exists vi; then
                    vi "$CROWDSEC_ACQUIS"
                else
                    ui_msgbox "Error" "No text editor found (nano or vi)"
                fi
                ;;
            test)
                local test_output
                test_output=$(crowdsec -t 2>&1)
                local exit_code=$?

                echo "$test_output" > /tmp/crowdsec_config_test.txt
                ui_textbox "Configuration Test" /tmp/crowdsec_config_test.txt
                rm -f /tmp/crowdsec_config_test.txt

                if [[ $exit_code -eq 0 ]]; then
                    if ui_yesno "Test Passed" "Configuration is valid!\n\nReload CrowdSec to apply changes?"; then
                        systemctl reload crowdsec
                        ui_msgbox "Success" "CrowdSec reloaded successfully"
                    fi
                else
                    ui_msgbox "Test Failed" "Configuration has errors.\n\nPlease fix the issues before reloading."
                fi
                ;;
        esac
    done
}

# Toggle simulation mode
toggle_simulation() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    if ! require_root; then
        return 1
    fi

    # Check current simulation status
    local current_status
    if grep -q "simulation: true" "$CROWDSEC_CONFIG" 2>/dev/null; then
        current_status="enabled"
    else
        current_status="disabled"
    fi

    local new_status
    if [[ "$current_status" == "enabled" ]]; then
        if ui_yesno "Disable Simulation Mode" "Simulation mode is currently ENABLED.\n\nDisable it to start creating real decisions (bans)?"; then
            new_status="false"
        else
            return
        fi
    else
        if ui_yesno "Enable Simulation Mode" "Simulation mode is currently DISABLED.\n\nEnable it to run scenarios without creating real bans?\n\n(Useful for testing)"; then
            new_status="true"
        else
            return
        fi
    fi

    # Update config
    if grep -q "simulation:" "$CROWDSEC_CONFIG"; then
        sed -i "s/simulation:.*/simulation: $new_status/" "$CROWDSEC_CONFIG"
    else
        echo "simulation: $new_status" >> "$CROWDSEC_CONFIG"
    fi

    # Reload
    systemctl reload crowdsec

    if [[ "$new_status" == "true" ]]; then
        log_info "Enabled CrowdSec simulation mode"
        ui_msgbox "Success" "Simulation mode ENABLED.\n\nScenarios will run but won't create real bans."
    else
        log_info "Disabled CrowdSec simulation mode"
        ui_msgbox "Success" "Simulation mode DISABLED.\n\nScenarios will now create real bans."
    fi
}

# Explain decision for IP
explain_decision() {
    if ! is_crowdsec_installed; then
        ui_msgbox "Error" "CrowdSec is not installed"
        return 1
    fi

    local ip
    ip=$(ui_inputbox "Explain Decision" "Enter IP address to investigate:") || return

    if ! validate_ip "$ip"; then
        ui_msgbox "Error" "Invalid IP address format"
        return 1
    fi

    local info=""
    info+="=== Decision Explanation for $ip ===\n\n"

    # Get decisions
    local decisions
    decisions=$(cscli decisions list --ip "$ip" 2>/dev/null)

    info+="--- Active Decisions ---\n"
    if [[ -z "$decisions" || $(echo "$decisions" | wc -l) -le 1 ]]; then
        info+="No active decisions\n"
    else
        info+="$decisions\n"
    fi

    info+="\n--- Alerts for this IP ---\n"

    # Get alerts
    local alerts
    alerts=$(cscli alerts list --ip "$ip" 2>/dev/null | head -20)

    if [[ -z "$alerts" || $(echo "$alerts" | wc -l) -le 1 ]]; then
        info+="No alerts found\n"
    else
        info+="$alerts\n"
    fi

    echo -e "$info" > /tmp/crowdsec_explain.txt
    ui_textbox "Decision Explanation: $ip" /tmp/crowdsec_explain.txt
    rm -f /tmp/crowdsec_explain.txt
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "CrowdSec Manager" "Select operation:" \
            "status" "Show CrowdSec status" \
            "decisions" "Show active decisions (bans)" \
            "" "" \
            "install" "Install CrowdSec" \
            "uninstall" "Uninstall CrowdSec" \
            "quick-setup" "Quick setup - Install common protection" \
            "" "" \
            "collections" "Manage collections" \
            "scenarios" "Show installed scenarios" \
            "bouncers" "Manage bouncers" \
            "whitelist" "Manage whitelist" \
            "" "" \
            "ban" "Manually ban an IP" \
            "unban" "Unban an IP" \
            "clear-bans" "Clear all bans" \
            "" "" \
            "console" "Console enrollment and status" \
            "acquisition" "Configure log sources" \
            "parsers" "Manage parsers" \
            "postoverflows" "Manage postoverflows" \
            "simulation" "Toggle simulation mode" \
            "explain" "Explain decision for IP" \
            "" "" \
            "service" "Service control (start/stop/restart)" \
            "logs" "View logs") || break

        case "$choice" in
            status) show_status ;;
            decisions) show_decisions ;;
            install) install_crowdsec ;;
            uninstall) uninstall_crowdsec ;;
            quick-setup) quick_setup ;;
            collections) manage_collections ;;
            scenarios) show_scenarios ;;
            bouncers) manage_bouncers ;;
            whitelist) manage_whitelist ;;
            ban) ban_ip ;;
            unban) unban_ip ;;
            clear-bans) clear_all_decisions ;;
            console) console_menu ;;
            acquisition) manage_acquisition ;;
            parsers) manage_parsers ;;
            postoverflows) manage_postoverflows ;;
            simulation) toggle_simulation ;;
            explain) explain_decision ;;
            service) service_control ;;
            logs) view_logs ;;
        esac
    done
}
