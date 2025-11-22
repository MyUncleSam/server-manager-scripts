#!/bin/bash
#
# Network Manager Module
# Manage network interfaces, IPv4 and IPv6 configuration
#

# Module metadata
module_info() {
    echo "Network Manager|Manage network interfaces and IP configuration"
}

# Netplan configuration directory
NETPLAN_DIR="/etc/netplan"

# Get primary network interface
get_primary_interface() {
    ip route | grep default | awk '{print $5}' | head -1
}

# Get all network interfaces (excluding lo)
get_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v "^lo$" | sort
}

# Show network status
show_status() {
    local info=""
    info+="=== Network Status ===\n\n"

    # Get interfaces
    local interfaces
    interfaces=$(get_interfaces)

    for iface in $interfaces; do
        info+="Interface: $iface\n"
        info+="─────────────────────────────────\n"

        # Status
        local state
        state=$(ip link show "$iface" | grep -o "state [A-Z]*" | awk '{print $2}')
        info+="  State:      $state\n"

        # MAC address
        local mac
        mac=$(ip link show "$iface" | grep -o "link/ether [^ ]*" | awk '{print $2}')
        if [[ -n "$mac" ]]; then
            info+="  MAC:        $mac\n"
        fi

        # IPv4 addresses
        local ipv4
        ipv4=$(ip -4 addr show "$iface" | grep "inet " | awk '{print $2}')
        if [[ -n "$ipv4" ]]; then
            info+="  IPv4:       $ipv4\n"
        else
            info+="  IPv4:       Not configured\n"
        fi

        # IPv6 addresses
        local ipv6
        ipv6=$(ip -6 addr show "$iface" | grep "inet6 " | grep -v "fe80::" | awk '{print $2}')
        if [[ -n "$ipv6" ]]; then
            info+="  IPv6:       $ipv6\n"
        else
            info+="  IPv6:       Not configured\n"
        fi

        # Gateway
        local gw4
        gw4=$(ip -4 route | grep "default.*$iface" | awk '{print $3}')
        if [[ -n "$gw4" ]]; then
            info+="  Gateway:    $gw4\n"
        fi

        info+="\n"
    done

    # DNS servers
    info+="=== DNS Servers ===\n\n"
    if [[ -f /etc/resolv.conf ]]; then
        local dns
        dns=$(grep "^nameserver" /etc/resolv.conf | awk '{print $2}')
        if [[ -n "$dns" ]]; then
            info+="$dns\n"
        else
            info+="No DNS servers configured\n"
        fi
    fi

    echo -e "$info" > /tmp/network_status.txt
    ui_textbox "Network Status" /tmp/network_status.txt
    rm -f /tmp/network_status.txt
}

# Select network interface
select_interface() {
    local interfaces
    interfaces=$(get_interfaces)

    if [[ -z "$interfaces" ]]; then
        ui_msgbox "Error" "No network interfaces found"
        return 1
    fi

    # Build menu
    local iface_list=()
    for iface in $interfaces; do
        local state
        state=$(ip link show "$iface" | grep -o "state [A-Z]*" | awk '{print $2}')
        local ipv4
        ipv4=$(ip -4 addr show "$iface" | grep "inet " | awk '{print $2}' | head -1)
        iface_list+=("$iface" "$state ${ipv4:-No IP}")
    done

    ui_menu "Select Interface" "Choose network interface:" "${iface_list[@]}"
}

# Get current netplan config file for interface
get_netplan_file() {
    local iface="$1"

    # Find existing config or use default
    local config_file
    config_file=$(grep -l "$iface" "$NETPLAN_DIR"/*.yaml 2>/dev/null | head -1)

    if [[ -z "$config_file" ]]; then
        config_file="$NETPLAN_DIR/01-netcfg.yaml"
    fi

    echo "$config_file"
}

# Get current IPv4 config from netplan file
get_current_ipv4_config() {
    local iface="$1"
    local config_file
    config_file=$(get_netplan_file "$iface")

    if [[ ! -f "$config_file" ]]; then
        echo "none"
        return
    fi

    local content
    content=$(cat "$config_file")

    # Check if dhcp4 is enabled
    if echo "$content" | grep -q "dhcp4: true"; then
        echo "dhcp4"
        return
    fi

    # Check for static IPv4 (has addresses with IPv4)
    if echo "$content" | grep -qE "^\s+- [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/"; then
        # Extract address, gateway, and DNS
        local addr gw dns_servers
        addr=$(echo "$content" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+" | head -1)
        gw=$(echo "$content" | grep -A1 "to: default" | grep "via:" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -1)
        dns_servers=$(echo "$content" | grep -A1 "addresses:" | grep -oE "\[[^]]+\]" | tr -d '[]' | head -1)
        echo "static4:$addr:$gw:$dns_servers"
        return
    fi

    # Check if dhcp4 is explicitly disabled
    if echo "$content" | grep -q "dhcp4: false"; then
        echo "disable4"
        return
    fi

    echo "none"
}

# Get current IPv6 config from netplan file
get_current_ipv6_config() {
    local iface="$1"
    local config_file
    config_file=$(get_netplan_file "$iface")

    if [[ ! -f "$config_file" ]]; then
        echo "none"
        return
    fi

    local content
    content=$(cat "$config_file")

    # Check for disabled IPv6 (link-local: [])
    if echo "$content" | grep -q "link-local: \[\]"; then
        echo "disable6"
        return
    fi

    # Check if dhcp6 is enabled with accept-ra (auto/SLAAC)
    if echo "$content" | grep -q "dhcp6: true" && echo "$content" | grep -q "ipv6-privacy: true"; then
        echo "auto6"
        return
    fi

    # Check if dhcp6 only
    if echo "$content" | grep -q "dhcp6: true"; then
        echo "dhcp6"
        return
    fi

    # Check for static IPv6
    if echo "$content" | grep -qE "^\s+- [0-9a-fA-F:]+/"; then
        local addr gw
        addr=$(echo "$content" | grep -oE "[0-9a-fA-F:]+/[0-9]+" | grep ":" | head -1)
        gw=$(echo "$content" | grep -A1 "to: ::/0" | grep "via:" | grep -oE "[0-9a-fA-F:]+" | grep ":" | head -1)
        echo "static6:$addr:$gw"
        return
    fi

    echo "none"
}

# Configure IPv4
configure_ipv4() {
    if ! require_root; then
        return 1
    fi

    local iface
    iface=$(select_interface) || return

    local mode
    mode=$(ui_menu "IPv4 Configuration" "Select IPv4 mode for $iface:" \
        "dhcp" "DHCP (automatic)" \
        "static" "Static IP address" \
        "disable" "Disable IPv4") || return

    local config_file
    config_file=$(get_netplan_file "$iface")

    # Backup existing config
    if [[ -f "$config_file" ]]; then
        backup_file "$config_file"
    fi

    # Get current IPv6 config to preserve it
    local current_ipv6
    current_ipv6=$(get_current_ipv6_config "$iface")

    case "$mode" in
        dhcp)
            create_netplan_config "$iface" "dhcp4" "" "" "" "$current_ipv6"
            ;;
        static)
            # Get IP address
            local ipaddr
            ipaddr=$(ui_inputbox "IPv4 Address" "Enter IPv4 address with CIDR (e.g., 192.168.1.100/24):") || return

            if [[ ! "$ipaddr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
                ui_msgbox "Error" "Invalid IP address format. Use CIDR notation (e.g., 192.168.1.100/24)"
                return 1
            fi

            # Get gateway
            local gateway
            gateway=$(ui_inputbox "Gateway" "Enter gateway address (e.g., 192.168.1.1):") || return

            # Get DNS
            local dns
            dns=$(ui_inputbox "DNS Servers" "Enter DNS servers (comma-separated, e.g., 8.8.8.8,8.8.4.4):" "8.8.8.8,8.8.4.4") || return

            create_netplan_config "$iface" "static4" "$ipaddr" "$gateway" "$dns" "$current_ipv6"
            ;;
        disable)
            create_netplan_config "$iface" "disable4" "" "" "" "$current_ipv6"
            ;;
    esac

    # Apply configuration
    if ui_yesno "Apply Configuration" "Apply network configuration now?\n\nWarning: This may disconnect your session."; then
        apply_netplan
    else
        ui_msgbox "Info" "Configuration saved but not applied.\n\nRun 'sudo netplan apply' to apply changes."
    fi
}

# Configure IPv6
configure_ipv6() {
    if ! require_root; then
        return 1
    fi

    local iface
    iface=$(select_interface) || return

    local mode
    mode=$(ui_menu "IPv6 Configuration" "Select IPv6 mode for $iface:" \
        "auto" "Automatic (SLAAC/DHCPv6)" \
        "dhcp" "DHCPv6 only" \
        "static" "Static IP address" \
        "disable" "Disable IPv6") || return

    local config_file
    config_file=$(get_netplan_file "$iface")

    # Backup existing config
    if [[ -f "$config_file" ]]; then
        backup_file "$config_file"
    fi

    # Get current IPv4 config to preserve it
    local current_ipv4
    current_ipv4=$(get_current_ipv4_config "$iface")

    # Parse current IPv4 settings
    local ipv4_mode="" ipv4_addr="" ipv4_gw="" dns=""
    case "$current_ipv4" in
        dhcp4)
            ipv4_mode="dhcp4"
            ;;
        static4:*)
            ipv4_mode="static4"
            IFS=':' read -ra parts <<< "${current_ipv4#static4:}"
            ipv4_addr="${parts[0]}"
            ipv4_gw="${parts[1]:-}"
            dns="${parts[2]:-}"
            ;;
        disable4)
            ipv4_mode="disable4"
            ;;
        none)
            ipv4_mode=""
            ;;
    esac

    case "$mode" in
        auto)
            create_netplan_config "$iface" "$ipv4_mode" "$ipv4_addr" "$ipv4_gw" "$dns" "auto6"
            ;;
        dhcp)
            create_netplan_config "$iface" "$ipv4_mode" "$ipv4_addr" "$ipv4_gw" "$dns" "dhcp6"
            ;;
        static)
            # Get IP address
            local ipaddr
            ipaddr=$(ui_inputbox "IPv6 Address" "Enter IPv6 address with prefix (e.g., 2001:db8::1/64):") || return

            # Get gateway
            local gateway
            gateway=$(ui_inputbox "Gateway" "Enter IPv6 gateway (leave empty if not needed):") || return

            create_netplan_config "$iface" "$ipv4_mode" "$ipv4_addr" "$ipv4_gw" "$dns" "static6:$ipaddr:$gateway"
            ;;
        disable)
            create_netplan_config "$iface" "$ipv4_mode" "$ipv4_addr" "$ipv4_gw" "$dns" "disable6"
            ;;
    esac

    # Apply configuration
    if ui_yesno "Apply Configuration" "Apply network configuration now?\n\nWarning: This may disconnect your session."; then
        apply_netplan
    else
        ui_msgbox "Info" "Configuration saved but not applied.\n\nRun 'sudo netplan apply' to apply changes."
    fi
}

# Create netplan configuration
create_netplan_config() {
    local iface="$1"
    local ipv4_mode="$2"
    local ipv4_addr="$3"
    local ipv4_gw="$4"
    local dns="$5"
    local ipv6_mode="$6"

    local config_file
    config_file=$(get_netplan_file "$iface")

    # Parse IPv6 static address (use | as delimiter since IPv6 has colons)
    local ipv6_addr="" ipv6_gw=""
    if [[ "$ipv6_mode" == static6:* ]]; then
        local ipv6_data="${ipv6_mode#static6:}"
        # Split on last colon before gateway (find the /prefix then next colon)
        if [[ "$ipv6_data" =~ ^(.+/[0-9]+):(.*)$ ]]; then
            ipv6_addr="${BASH_REMATCH[1]}"
            ipv6_gw="${BASH_REMATCH[2]}"
        else
            ipv6_addr="$ipv6_data"
        fi
    fi

    # Start building config
    local config=""
    config+="network:\n"
    config+="  version: 2\n"
    config+="  renderer: networkd\n"
    config+="  ethernets:\n"
    config+="    $iface:\n"

    # Determine if we need addresses section
    local has_addresses=false
    [[ "$ipv4_mode" == "static4" && -n "$ipv4_addr" ]] && has_addresses=true
    [[ "$ipv6_mode" == static6:* && -n "$ipv6_addr" ]] && has_addresses=true

    # IPv4 DHCP setting
    case "$ipv4_mode" in
        dhcp4)
            config+="      dhcp4: true\n"
            ;;
        static4|disable4)
            config+="      dhcp4: false\n"
            ;;
        ""|none)
            # No IPv4 config specified, default to DHCP
            config+="      dhcp4: true\n"
            ;;
    esac

    # IPv6 DHCP/auto setting
    case "$ipv6_mode" in
        auto6)
            config+="      dhcp6: true\n"
            config+="      ipv6-privacy: true\n"
            ;;
        dhcp6)
            config+="      dhcp6: true\n"
            config+="      accept-ra: false\n"
            ;;
        static6:*|disable6)
            config+="      dhcp6: false\n"
            ;;
        ""|none)
            # No IPv6 config specified, default to auto
            config+="      dhcp6: true\n"
            config+="      ipv6-privacy: true\n"
            ;;
    esac

    # Add addresses section if needed
    if [[ "$has_addresses" == true ]]; then
        config+="      addresses:\n"
        [[ "$ipv4_mode" == "static4" && -n "$ipv4_addr" ]] && config+="        - $ipv4_addr\n"
        [[ -n "$ipv6_addr" ]] && config+="        - $ipv6_addr\n"
    fi

    # Add routes if needed
    local has_routes=false
    [[ "$ipv4_mode" == "static4" && -n "$ipv4_gw" ]] && has_routes=true
    [[ -n "$ipv6_gw" ]] && has_routes=true

    if [[ "$has_routes" == true ]]; then
        config+="      routes:\n"
        if [[ "$ipv4_mode" == "static4" && -n "$ipv4_gw" ]]; then
            config+="        - to: default\n"
            config+="          via: $ipv4_gw\n"
        fi
        if [[ -n "$ipv6_gw" ]]; then
            config+="        - to: ::/0\n"
            config+="          via: $ipv6_gw\n"
        fi
    fi

    # Add nameservers if DNS specified
    if [[ -n "$dns" ]]; then
        config+="      nameservers:\n"
        config+="        addresses: [${dns}]\n"
    fi

    # Add IPv6 disable specifics
    if [[ "$ipv6_mode" == "disable6" ]]; then
        config+="      accept-ra: false\n"
        config+="      link-local: []\n"
    fi

    # Write config file
    echo -e "$config" > "$config_file"
    chmod 600 "$config_file"

    log_info "Network configuration saved: $config_file"
}

# Apply netplan configuration
apply_netplan() {
    ui_infobox "Applying" "Applying network configuration..."

    local output
    output=$(netplan apply 2>&1)

    if [[ $? -eq 0 ]]; then
        log_info "Network configuration applied"
        ui_msgbox "Success" "Network configuration applied successfully"
    else
        ui_msgbox "Error" "Failed to apply configuration:\n\n$output"
        return 1
    fi
}

# Disable IPv6 system-wide
disable_ipv6_system() {
    if ! require_root; then
        return 1
    fi

    if ui_yesno "Disable IPv6" "Disable IPv6 system-wide?\n\nThis will add kernel parameters to /etc/sysctl.conf"; then
        # Add sysctl parameters
        local sysctl_file="/etc/sysctl.d/99-disable-ipv6.conf"

        cat > "$sysctl_file" << 'EOF'
# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

        # Apply immediately
        sysctl -p "$sysctl_file"

        log_info "IPv6 disabled system-wide"
        ui_msgbox "Success" "IPv6 has been disabled system-wide.\n\nThis will persist across reboots."
    fi
}

# Enable IPv6 system-wide
enable_ipv6_system() {
    if ! require_root; then
        return 1
    fi

    local sysctl_file="/etc/sysctl.d/99-disable-ipv6.conf"

    if [[ -f "$sysctl_file" ]]; then
        rm -f "$sysctl_file"

        # Re-enable IPv6
        sysctl -w net.ipv6.conf.all.disable_ipv6=0
        sysctl -w net.ipv6.conf.default.disable_ipv6=0
        sysctl -w net.ipv6.conf.lo.disable_ipv6=0

        log_info "IPv6 enabled system-wide"
        ui_msgbox "Success" "IPv6 has been enabled system-wide."
    else
        ui_msgbox "Info" "IPv6 is not disabled system-wide."
    fi
}

# Show current netplan configuration
show_netplan_config() {
    local configs
    configs=$(ls "$NETPLAN_DIR"/*.yaml 2>/dev/null)

    if [[ -z "$configs" ]]; then
        ui_msgbox "Info" "No netplan configuration files found"
        return
    fi

    local all_config=""
    for config in $configs; do
        all_config+="=== $config ===\n\n"
        all_config+=$(cat "$config")
        all_config+="\n\n"
    done

    echo -e "$all_config" > /tmp/netplan_config.txt
    ui_textbox "Netplan Configuration" /tmp/netplan_config.txt
    rm -f /tmp/netplan_config.txt
}

# Configure DNS servers
configure_dns() {
    if ! require_root; then
        return 1
    fi

    local iface
    iface=$(select_interface) || return

    local dns
    dns=$(ui_inputbox "DNS Servers" "Enter DNS servers (comma-separated):" "8.8.8.8,8.8.4.4") || return

    if [[ -z "$dns" ]]; then
        ui_msgbox "Error" "DNS servers cannot be empty"
        return 1
    fi

    local config_file
    config_file=$(get_netplan_file "$iface")

    # This is a simplified approach - ideally we'd parse and update the existing config
    ui_msgbox "Info" "DNS configuration should be set when configuring IPv4.\n\nPlease use 'Configure IPv4' with static IP to set DNS servers."
}

# Restart networking
restart_networking() {
    if ! require_root; then
        return 1
    fi

    if ui_yesno "Restart Networking" "Restart networking services?\n\nWarning: This may disconnect your session."; then
        ui_infobox "Restarting" "Restarting network services..."

        netplan apply
        systemctl restart systemd-networkd 2>/dev/null

        log_info "Network services restarted"
        ui_msgbox "Success" "Network services restarted"
    fi
}

# Quick setup - configure interface with common settings
quick_setup() {
    if ! require_root; then
        return 1
    fi

    local iface
    iface=$(select_interface) || return

    ui_msgbox "Quick Setup" "Configure $iface with common settings.\n\nYou will set:\n• IPv4 (DHCP or Static)\n• IPv6 (Auto or Disable)"

    # IPv4 mode
    local ipv4_mode
    ipv4_mode=$(ui_radiolist "IPv4 Mode" "Select IPv4 configuration:" \
        "dhcp" "DHCP (automatic)" "on" \
        "static" "Static IP" "off") || return

    local ipv4_addr="" ipv4_gw="" dns=""

    if [[ "$ipv4_mode" == "static" ]]; then
        ipv4_addr=$(ui_inputbox "IPv4 Address" "Enter IPv4 address (CIDR, e.g., 192.168.1.100/24):") || return
        ipv4_gw=$(ui_inputbox "Gateway" "Enter gateway:") || return
        dns=$(ui_inputbox "DNS" "Enter DNS servers:" "8.8.8.8,8.8.4.4") || return
    fi

    # IPv6 mode
    local ipv6_mode
    ipv6_mode=$(ui_radiolist "IPv6 Mode" "Select IPv6 configuration:" \
        "auto" "Automatic (SLAAC)" "on" \
        "disable" "Disable IPv6" "off") || return

    # Build and save config
    local config_file
    config_file=$(get_netplan_file "$iface")
    backup_file "$config_file" 2>/dev/null

    if [[ "$ipv4_mode" == "dhcp" ]]; then
        create_netplan_config "$iface" "dhcp4" "" "" "" "${ipv6_mode}6"
    else
        create_netplan_config "$iface" "static4" "$ipv4_addr" "$ipv4_gw" "$dns" "${ipv6_mode}6"
    fi

    # Apply
    if ui_yesno "Apply Configuration" "Apply network configuration?\n\nInterface: $iface\nIPv4: $ipv4_mode\nIPv6: $ipv6_mode"; then
        apply_netplan
    fi
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "Network Manager" "Select operation:" \
            "status" "Show network status" \
            "quick" "Quick setup" \
            "ipv4" "Configure IPv4" \
            "ipv6" "Configure IPv6" \
            "disable-ipv6" "Disable IPv6 system-wide" \
            "enable-ipv6" "Enable IPv6 system-wide" \
            "config" "Show netplan configuration" \
            "apply" "Apply netplan configuration" \
            "restart" "Restart networking") || break

        case "$choice" in
            status)       show_status ;;
            quick)        quick_setup ;;
            ipv4)         configure_ipv4 ;;
            ipv6)         configure_ipv6 ;;
            disable-ipv6) disable_ipv6_system ;;
            enable-ipv6)  enable_ipv6_system ;;
            config)       show_netplan_config ;;
            apply)        apply_netplan ;;
            restart)      restart_networking ;;
        esac
    done
}
