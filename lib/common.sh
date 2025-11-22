#!/bin/bash
#
# Common Helper Library - Utility functions for modules
#

#=============================================================================
# System Check Functions
#=============================================================================

# Check if running as root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Require root privileges
require_root() {
    if ! is_root; then
        ui_msgbox "Error" "This operation requires root privileges.\nPlease run the script with sudo."
        return 1
    fi
    return 0
}

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Check if a package is installed
package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

#=============================================================================
# Package Management
#=============================================================================

# Install packages with apt
install_packages() {
    local packages=("$@")

    if ! require_root; then
        return 1
    fi

    (
        echo "10"
        apt-get update -qq 2>&1
        echo "30"
        apt-get install -y "${packages[@]}" 2>&1
        echo "100"
    ) | ui_gauge "Installing Packages" "Installing: ${packages[*]}"
}

# Remove packages with apt
remove_packages() {
    local packages=("$@")

    if ! require_root; then
        return 1
    fi

    apt-get remove -y "${packages[@]}" 2>&1 | ui_progressbox "Removing Packages"
}

#=============================================================================
# Service Management
#=============================================================================

# Start a service
service_start() {
    local service="$1"
    systemctl start "$service"
}

# Stop a service
service_stop() {
    local service="$1"
    systemctl stop "$service"
}

# Restart a service
service_restart() {
    local service="$1"
    systemctl restart "$service"
}

# Enable a service
service_enable() {
    local service="$1"
    systemctl enable "$service"
}

# Check if a service is running
service_is_running() {
    local service="$1"
    systemctl is-active --quiet "$service"
}

# Get service status
service_status() {
    local service="$1"
    systemctl status "$service" --no-pager
}

#=============================================================================
# File Operations
#=============================================================================

# Backup a file
backup_file() {
    local file="$1"
    local backup="${file}.bak.$(date +%Y%m%d_%H%M%S)"

    if [[ -f "$file" ]]; then
        cp "$file" "$backup"
        echo "$backup"
    fi
}

# Create directory if it doesn't exist
ensure_dir() {
    local dir="$1"
    mkdir -p "$dir"
}

# Download a file
download_file() {
    local url="$1"
    local dest="$2"

    if command_exists wget; then
        wget -q -O "$dest" "$url"
    elif command_exists curl; then
        curl -sSL -o "$dest" "$url"
    else
        return 1
    fi
}

#=============================================================================
# User Management Helpers
#=============================================================================

# Get list of regular users (UID >= 1000)
get_regular_users() {
    awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd
}

# Get list of all groups
get_all_groups() {
    cut -d: -f1 /etc/group | sort
}

# Get user's groups
get_user_groups() {
    local username="$1"
    id -nG "$username" 2>/dev/null
}

# Check if user exists
user_exists() {
    local username="$1"
    id "$username" &>/dev/null
}

# Check if group exists
group_exists() {
    local groupname="$1"
    getent group "$groupname" &>/dev/null
}

#=============================================================================
# Network Helpers
#=============================================================================

# Get primary IP address
get_primary_ip() {
    hostname -I | awk '{print $1}'
}

# Check if port is in use
port_in_use() {
    local port="$1"
    ss -tuln | grep -q ":$port "
}

# Check internet connectivity
has_internet() {
    ping -c 1 -W 2 8.8.8.8 &>/dev/null
}

#=============================================================================
# Logging Functions
#=============================================================================

# Log directory
LOG_DIR="${SCRIPT_DIR:-/tmp}/logs"
LOG_FILE="${LOG_DIR}/server-manager.log"

# Initialize logging (called automatically)
init_logging() {
    mkdir -p "$LOG_DIR" 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null
}

# Log a message
log_message() {
    local level="$1"
    local message="$2"

    # Ensure log directory exists
    if [[ ! -d "$LOG_DIR" ]]; then
        init_logging
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE" 2>/dev/null
}

log_info() {
    log_message "INFO" "$1"
}

log_warn() {
    log_message "WARN" "$1"
}

log_error() {
    log_message "ERROR" "$1"
}

#=============================================================================
# Validation Functions
#=============================================================================

# Validate username
validate_username() {
    local username="$1"
    [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]] && [[ ${#username} -le 32 ]]
}

# Validate IP address
validate_ip() {
    local ip="$1"
    [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
}

# Validate port number
validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [[ $port -ge 1 ]] && [[ $port -le 65535 ]]
}

#=============================================================================
# Formatting Functions
#=============================================================================

# Format bytes to human readable
format_bytes() {
    local bytes="$1"
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$((bytes / 1024))KB"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

# Format seconds to human readable
format_duration() {
    local seconds="$1"
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))

    if [[ $days -gt 0 ]]; then
        echo "${days}d ${hours}h ${minutes}m"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}
