#!/bin/bash
#
# APT Manager Module
# Manage and maintain APT packages and updates
#

# Module metadata
module_info() {
    echo "APT|Manage packages, updates, and maintenance"
}

# Update package lists
update_package_lists() {
    if ! require_root; then
        return 1
    fi

    ui_infobox "Updating" "Updating package lists..."

    local output
    output=$(apt-get update 2>&1)
    local status=$?

    if [[ $status -eq 0 ]]; then
        log_info "Package lists updated"
        ui_msgbox "Success" "Package lists updated successfully"
    else
        ui_msgbox "Error" "Failed to update package lists:\n\n$output"
    fi
}

# Check and install updates
install_updates() {
    if ! require_root; then
        return 1
    fi

    ui_infobox "Checking" "Checking for updates..."
    apt-get update -qq 2>&1

    # Get list of upgradable packages
    local updates
    updates=$(apt list --upgradable 2>/dev/null | tail -n +2 | cut -d'/' -f1)

    if [[ -z "$updates" ]]; then
        ui_msgbox "Up to Date" "No updates available."
        return 0
    fi

    # Build checklist with all packages preselected
    local pkg_list=()
    while IFS= read -r pkg; do
        if [[ -n "$pkg" ]]; then
            local current_ver new_ver
            current_ver=$(dpkg -l "$pkg" 2>/dev/null | grep "^ii" | awk '{print $3}' | cut -c1-20)
            new_ver=$(apt-cache policy "$pkg" 2>/dev/null | grep "Candidate:" | awk '{print $2}' | cut -c1-20)
            pkg_list+=("$pkg" "$current_ver -> $new_ver" "on")
        fi
    done <<< "$updates"

    if [[ ${#pkg_list[@]} -eq 0 ]]; then
        ui_msgbox "Up to Date" "No updates available."
        return 0
    fi

    # Show checklist for package selection
    local selected
    selected=$(ui_checklist "Select Updates" "Select packages to update:" "${pkg_list[@]}") || return

    if [[ -z "$selected" ]]; then
        ui_msgbox "Cancelled" "No packages selected for update."
        return 0
    fi

    # Convert selection to package list
    local packages_to_update=""
    for pkg in $selected; do
        pkg=$(echo "$pkg" | tr -d '"')
        packages_to_update+="$pkg "
    done

    # Confirm update
    local pkg_count
    pkg_count=$(echo "$packages_to_update" | wc -w)

    if ! ui_yesno "Confirm Update" "Update $pkg_count package(s)?\n\n$packages_to_update"; then
        return
    fi

    # Install selected updates
    (
        echo 10
        apt-get install -y $packages_to_update 2>&1
        echo 100
    ) | ui_gauge "Installing Updates" "Please wait..."

    log_info "Updated packages: $packages_to_update"
    ui_msgbox "Complete" "Updates installed successfully."
}

# Install a package
install_package() {
    if ! require_root; then
        return 1
    fi

    local package
    package=$(ui_inputbox "Install Package" "Enter package name to install:") || return

    if [[ -z "$package" ]]; then
        return
    fi

    # Check if package exists
    if ! apt-cache show "$package" &>/dev/null; then
        ui_msgbox "Error" "Package '$package' not found"
        return 1
    fi

    # Check if already installed
    if package_installed "$package"; then
        if ! ui_yesno "Already Installed" "Package '$package' is already installed.\n\nReinstall?"; then
            return
        fi
    fi

    # Install package
    (
        echo 10
        apt-get update -qq 2>&1
        echo 30
        apt-get install -y "$package" 2>&1
        echo 100
    ) | ui_gauge "Installing" "Installing $package..."

    if package_installed "$package"; then
        log_info "Installed package: $package"
        ui_msgbox "Success" "Package '$package' installed successfully"
    else
        ui_msgbox "Error" "Failed to install '$package'"
    fi
}

# Remove a package
remove_package() {
    if ! require_root; then
        return 1
    fi

    local package
    package=$(ui_inputbox "Remove Package" "Enter package name to remove:") || return

    if [[ -z "$package" ]]; then
        return
    fi

    if ! package_installed "$package"; then
        ui_msgbox "Error" "Package '$package' is not installed"
        return 1
    fi

    # Ask about purge
    local purge=""
    if ui_yesno "Purge Config" "Also remove configuration files?"; then
        purge="--purge"
    fi

    if ui_yesno "Confirm Remove" "Remove package '$package'?"; then
        apt-get remove $purge -y "$package" 2>&1 | ui_progressbox "Removing Package"

        log_info "Removed package: $package"
        ui_msgbox "Success" "Package '$package' removed"
    fi
}

# Search for packages
search_packages() {
    local query
    query=$(ui_inputbox "Search Packages" "Enter search term:") || return

    if [[ -z "$query" ]]; then
        return
    fi

    ui_infobox "Searching" "Searching for '$query'..."

    local results
    results=$(apt-cache search "$query" 2>/dev/null | head -100)

    if [[ -z "$results" ]]; then
        ui_msgbox "No Results" "No packages found matching '$query'"
    else
        local count
        count=$(echo "$results" | wc -l)
        echo -e "=== Search Results ($count) ===\n\n$results" > /tmp/apt_search.txt
        ui_textbox "Search Results" /tmp/apt_search.txt
        rm -f /tmp/apt_search.txt
    fi
}

# Show package info
show_package_info() {
    local package
    package=$(ui_inputbox "Package Info" "Enter package name:") || return

    if [[ -z "$package" ]]; then
        return
    fi

    local info
    info=$(apt-cache show "$package" 2>&1)

    if [[ $? -eq 0 ]]; then
        echo "$info" > /tmp/pkg_info.txt
        ui_textbox "Package: $package" /tmp/pkg_info.txt
        rm -f /tmp/pkg_info.txt
    else
        ui_msgbox "Error" "Package '$package' not found"
    fi
}

# List installed packages
list_installed() {
    local filter
    filter=$(ui_inputbox "List Installed" "Enter filter (leave empty for all):" "") || return

    local packages
    if [[ -n "$filter" ]]; then
        packages=$(dpkg -l | grep "^ii" | grep -i "$filter" | awk '{print $2 " - " $3}')
    else
        packages=$(dpkg -l | grep "^ii" | awk '{print $2 " - " $3}')
    fi

    if [[ -z "$packages" ]]; then
        ui_msgbox "No Results" "No packages found"
    else
        local count
        count=$(echo "$packages" | wc -l)
        echo -e "=== Installed Packages ($count) ===\n\n$packages" > /tmp/installed.txt
        ui_textbox "Installed Packages" /tmp/installed.txt
        rm -f /tmp/installed.txt
    fi
}

# Install common packages
install_common_packages() {
    if ! require_root; then
        return 1
    fi

    # Define common packages (sorted alphabetically, excludes packages from other modules)
    declare -A common_packages=(
        ["apt-transport-https"]="APT HTTPS transport|off"
        ["build-essential"]="Build tools (gcc, make)|off"
        ["ca-certificates"]="Common CA certificates|on"
        ["curl"]="Data transfer tool|on"
        ["dnsutils"]="DNS utilities (dig, nslookup)|off"
        ["git"]="Version control system|off"
        ["gnupg"]="GNU privacy guard|on"
        ["gpg"]="GNU Privacy Guard|on"
        ["htop"]="Interactive process viewer|on"
        ["iftop"]="Display bandwidth usage|on"
        ["iotop"]="I/O monitor|on"
        ["iptraf-ng"]="Interactive IP traffic monitor|on"
        ["jq"]="JSON processor|on"
        ["logrotate"]="Log rotation|off"
        ["lsb-release"]="LSB release info|on"
        ["mc"]="Midnight Commander file manager|on"
        ["mtr-tiny"]="Network diagnostic tool|off"
        ["multitail"]="View multiple logfiles|on"
        ["nano"]="Simple text editor|off"
        ["ncdu"]="NCurses disk usage|off"
        ["net-tools"]="Network tools (ifconfig, etc)|off"
        ["p7zip-full"]="7zip compression|off"
        ["rsync"]="File synchronization|off"
        ["screen"]="Terminal multiplexer|off"
        ["software-properties-common"]="Manage repositories|off"
        ["tmux"]="Terminal multiplexer|off"
        ["traceroute"]="Trace network path|off"
        ["tree"]="Directory listing as tree|off"
        ["unzip"]="ZIP decompression|off"
        ["vim"]="Vi IMproved - enhanced vi editor|on"
        ["wget"]="Network downloader|on"
        ["zip"]="ZIP compression|off"
    )

    # Build checklist excluding already installed packages
    local pkg_list=()
    for pkg in $(echo "${!common_packages[@]}" | tr ' ' '\n' | sort); do
        if ! package_installed "$pkg"; then
            local desc default
            desc=$(echo "${common_packages[$pkg]}" | cut -d'|' -f1)
            default=$(echo "${common_packages[$pkg]}" | cut -d'|' -f2)
            pkg_list+=("$pkg" "$desc" "$default")
        fi
    done

    if [[ ${#pkg_list[@]} -eq 0 ]]; then
        ui_msgbox "All Installed" "All common packages are already installed."
        return 0
    fi

    local packages
    packages=$(ui_checklist "Common Packages" "Select packages to install:" "${pkg_list[@]}") || return

    if [[ -z "$packages" ]]; then
        ui_msgbox "Cancelled" "No packages selected"
        return
    fi

    # Convert to space-separated list
    local pkg_list=""
    for pkg in $packages; do
        pkg=$(echo "$pkg" | tr -d '"')
        pkg_list+="$pkg "
    done

    local pkg_count
    pkg_count=$(echo "$pkg_list" | wc -w)

    if ! ui_yesno "Confirm Install" "Install $pkg_count package(s)?"; then
        return
    fi

    # Install packages
    (
        echo 5
        apt-get update -qq 2>&1
        echo 15
        apt-get install -y $pkg_list 2>&1
        echo 100
    ) | ui_gauge "Installing Packages" "Please wait..."

    log_info "Installed common packages: $pkg_list"
    ui_msgbox "Complete" "Common packages installed successfully"
}

# Clean up APT cache
cleanup_apt() {
    if ! require_root; then
        return 1
    fi

    local choice
    choice=$(ui_checklist "Cleanup Options" "Select cleanup operations:" \
        "autoremove" "Remove unused packages" "on" \
        "autoclean" "Clean old package files" "on" \
        "clean" "Clean all cached packages" "off") || return

    if [[ -z "$choice" ]]; then
        return
    fi

    local operations=""
    for op in $choice; do
        op=$(echo "$op" | tr -d '"')
        operations+="$op "
    done

    (
        local progress=10
        for op in $operations; do
            case "$op" in
                autoremove)
                    apt-get autoremove -y 2>&1
                    ;;
                autoclean)
                    apt-get autoclean -y 2>&1
                    ;;
                clean)
                    apt-get clean 2>&1
                    ;;
            esac
            progress=$((progress + 30))
            echo $progress
        done
        echo 100
    ) | ui_gauge "Cleaning Up" "Please wait..."

    log_info "APT cleanup completed: $operations"
    ui_msgbox "Complete" "Cleanup completed"
}

# Fix broken packages
fix_broken() {
    if ! require_root; then
        return 1
    fi

    if ui_yesno "Fix Broken" "Attempt to fix broken packages?\n\nThis will run:\n• apt-get --fix-broken install\n• dpkg --configure -a"; then
        (
            echo 10
            dpkg --configure -a 2>&1
            echo 50
            apt-get --fix-broken install -y 2>&1
            echo 100
        ) | ui_gauge "Fixing Packages" "Please wait..."

        log_info "Attempted to fix broken packages"
        ui_msgbox "Complete" "Fix attempt completed"
    fi
}

# Show APT history
show_apt_history() {
    local log_file="/var/log/apt/history.log"

    if [[ -f "$log_file" ]]; then
        tail -500 "$log_file" > /tmp/apt_history.txt
        ui_textbox "APT History" /tmp/apt_history.txt
        rm -f /tmp/apt_history.txt
    else
        ui_msgbox "Error" "APT history log not found"
    fi
}

# Add PPA repository
add_ppa() {
    if ! require_root; then
        return 1
    fi

    # Check if add-apt-repository is available
    if ! command_exists add-apt-repository; then
        if ui_yesno "Install Required" "software-properties-common is required.\n\nInstall it now?"; then
            apt-get install -y software-properties-common
        else
            return 1
        fi
    fi

    local ppa
    ppa=$(ui_inputbox "Add PPA" "Enter PPA (e.g., ppa:user/repository):") || return

    if [[ -z "$ppa" ]]; then
        return
    fi

    if add-apt-repository -y "$ppa" 2>&1 | ui_progressbox "Adding PPA"; then
        apt-get update -qq
        log_info "Added PPA: $ppa"
        ui_msgbox "Success" "PPA added: $ppa"
    else
        ui_msgbox "Error" "Failed to add PPA"
    fi
}

# Show disk usage by APT
show_cache_size() {
    local info=""
    info+="=== APT Cache Information ===\n\n"

    # Cache size
    local cache_size
    cache_size=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
    info+="Package cache:    $cache_size\n"

    # Lists size
    local lists_size
    lists_size=$(du -sh /var/lib/apt/lists 2>/dev/null | cut -f1)
    info+="Package lists:    $lists_size\n"

    # Number of installed packages
    local pkg_count
    pkg_count=$(dpkg -l | grep "^ii" | wc -l)
    info+="Installed pkgs:   $pkg_count\n"

    # Upgradable packages
    local upgradable
    upgradable=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)
    info+="Upgradable:       $upgradable\n"

    # Auto-removable
    local autoremove
    autoremove=$(apt-get --dry-run autoremove 2>/dev/null | grep "^Remv" | wc -l)
    info+="Auto-removable:   $autoremove\n"

    echo -e "$info" > /tmp/apt_cache_info.txt
    ui_textbox "APT Cache Info" /tmp/apt_cache_info.txt
    rm -f /tmp/apt_cache_info.txt
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "APT" "Select operation:" \
            "updates" "Check and install updates" \
            "refresh" "Update package lists" \
            "common" "Install common packages" \
            "install" "Install package" \
            "remove" "Remove package" \
            "search" "Search packages" \
            "info" "Show package info" \
            "list" "List installed packages" \
            "cleanup" "Clean up APT cache" \
            "fix" "Fix broken packages" \
            "ppa" "Add PPA repository" \
            "cache" "Show cache info" \
            "history" "Show APT history") || break

        case "$choice" in
            updates) install_updates ;;
            refresh) update_package_lists ;;
            common)  install_common_packages ;;
            install) install_package ;;
            remove)  remove_package ;;
            search)  search_packages ;;
            info)    show_package_info ;;
            list)    list_installed ;;
            cleanup) cleanup_apt ;;
            fix)     fix_broken ;;
            ppa)     add_ppa ;;
            cache)   show_cache_size ;;
            history) show_apt_history ;;
        esac
    done
}
