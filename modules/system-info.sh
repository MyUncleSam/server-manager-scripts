#!/bin/bash
#
# System Information Module
# Display various system information
#

# Module metadata
module_info() {
    echo "System Info|Display system information and statistics"
}

# Get basic system info
show_basic_info() {
    local info=""

    # Hostname and OS
    info+="=== System Overview ===\n\n"
    info+="Hostname:     $(hostname)\n"
    info+="OS:           $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)\n"
    info+="Kernel:       $(uname -r)\n"
    info+="Architecture: $(uname -m)\n"

    # Uptime
    local uptime_sec
    uptime_sec=$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)
    info+="Uptime:       $(format_duration "$uptime_sec")\n"

    # CPU Info
    local cpu_model
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)
    local cpu_cores
    cpu_cores=$(nproc)
    info+="\n=== CPU ===\n\n"
    info+="Model:        $cpu_model\n"
    info+="Cores:        $cpu_cores\n"

    # CPU Usage
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    info+="Usage:        ${cpu_usage}%\n"

    # Memory
    local mem_total mem_used mem_free mem_percent
    read -r mem_total mem_used mem_free <<< $(free -m | awk 'NR==2{print $2, $3, $4}')
    mem_percent=$((mem_used * 100 / mem_total))
    info+="\n=== Memory ===\n\n"
    info+="Total:        ${mem_total}MB\n"
    info+="Used:         ${mem_used}MB (${mem_percent}%)\n"
    info+="Free:         ${mem_free}MB\n"

    # Swap
    local swap_total swap_used
    read -r swap_total swap_used <<< $(free -m | awk 'NR==3{print $2, $3}')
    if [[ $swap_total -gt 0 ]]; then
        info+="Swap Total:   ${swap_total}MB\n"
        info+="Swap Used:    ${swap_used}MB\n"
    fi

    # Disk
    info+="\n=== Disk Usage ===\n\n"
    info+="$(df -h --output=target,size,used,avail,pcent -x tmpfs -x devtmpfs | head -10)\n"

    # Network
    local primary_ip
    primary_ip=$(get_primary_ip)
    info+="\n=== Network ===\n\n"
    info+="Primary IP:   $primary_ip\n"

    # Show network interfaces
    info+="Interfaces:\n"
    while read -r iface; do
        local ip_addr
        ip_addr=$(ip -4 addr show "$iface" 2>/dev/null | grep inet | awk '{print $2}')
        if [[ -n "$ip_addr" ]]; then
            info+="  $iface: $ip_addr\n"
        fi
    done < <(ls /sys/class/net/ | grep -v lo)

    # Write to temp file and display
    echo -e "$info" > /tmp/system_info.txt
    ui_textbox "System Information" /tmp/system_info.txt
    rm -f /tmp/system_info.txt
}

# Show running services
show_services() {
    local services
    services=$(systemctl list-units --type=service --state=running --no-pager --no-legend | awk '{print $1, $4}' | head -30)

    echo -e "=== Running Services ===\n\n$services" > /tmp/services_info.txt
    ui_textbox "Running Services" /tmp/services_info.txt
    rm -f /tmp/services_info.txt
}

# Show listening ports
show_ports() {
    local ports
    ports=$(ss -tuln | grep LISTEN | awk '{print $1, $5}' | sort -t: -k2 -n)

    echo -e "=== Listening Ports ===\n\nProto Address\n$ports" > /tmp/ports_info.txt
    ui_textbox "Listening Ports" /tmp/ports_info.txt
    rm -f /tmp/ports_info.txt
}

# Show top processes
show_processes() {
    local processes
    processes=$(ps aux --sort=-%mem | head -20 | awk '{printf "%-10s %5s %5s %s\n", $1, $3, $4, $11}')

    echo -e "=== Top Processes (by Memory) ===\n\nUSER       %CPU  %MEM COMMAND\n$processes" > /tmp/proc_info.txt
    ui_textbox "Top Processes" /tmp/proc_info.txt
    rm -f /tmp/proc_info.txt
}

# Show disk I/O
show_disk_io() {
    if ! command_exists iostat; then
        ui_msgbox "Error" "iostat not found. Install with: apt install sysstat"
        return
    fi

    local io_info
    io_info=$(iostat -d -h 1 1)

    echo -e "=== Disk I/O Statistics ===\n\n$io_info" > /tmp/io_info.txt
    ui_textbox "Disk I/O" /tmp/io_info.txt
    rm -f /tmp/io_info.txt
}

# Show security information
show_security_info() {
    local info=""

    info+="=== Security Information ===\n\n"

    # UFW status
    if command_exists ufw; then
        local ufw_status
        ufw_status=$(ufw status 2>/dev/null | head -1)
        info+="UFW Firewall: $ufw_status\n"
    else
        info+="UFW Firewall: Not installed\n"
    fi

    # SSH config
    if [[ -f /etc/ssh/sshd_config ]]; then
        local root_login
        root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
        info+="SSH Root Login: ${root_login:-default (yes)}\n"

        local pass_auth
        pass_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
        info+="SSH Password Auth: ${pass_auth:-default (yes)}\n"
    fi

    # Failed login attempts
    local failed_logins
    failed_logins=$(grep "Failed password" /var/log/auth.log 2>/dev/null | wc -l)
    info+="Failed SSH logins: $failed_logins\n"

    # Last logins
    info+="\n=== Last Logins ===\n\n"
    info+="$(last -n 10 2>/dev/null)\n"

    # Updates available
    if command_exists apt; then
        local updates
        updates=$(apt list --upgradable 2>/dev/null | grep -c upgradable || echo "0")
        info+="\n=== Updates ===\n\n"
        info+="Packages upgradable: $updates\n"
    fi

    echo -e "$info" > /tmp/security_info.txt
    ui_textbox "Security Information" /tmp/security_info.txt
    rm -f /tmp/security_info.txt
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "System Information" "Select information to view:" \
            "basic" "Basic system information" \
            "services" "Running services" \
            "ports" "Listening ports" \
            "processes" "Top processes" \
            "disk_io" "Disk I/O statistics" \
            "security" "Security information") || break

        case "$choice" in
            basic)     show_basic_info ;;
            services)  show_services ;;
            ports)     show_ports ;;
            processes) show_processes ;;
            disk_io)   show_disk_io ;;
            security)  show_security_info ;;
        esac
    done
}
