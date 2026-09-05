#!/bin/bash
#
# Ubuntu Server Manager - Modular Server Management Tool
# A dialog-based TUI for managing Ubuntu servers
#

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"
LIB_DIR="${SCRIPT_DIR}/lib"
SKIP_DEPS_FILE="${SCRIPT_DIR}/DISABLE_DEPENDENCY_CHECK"

# Source libraries
source "${LIB_DIR}/ui.sh"
source "${LIB_DIR}/common.sh"

# Bypass the dependency check (useful on non-Debian distributions).
# Enabled by --skip-dependency-check, the DISABLE_DEPENDENCY_CHECK file
# or SERVER_MANAGER_SKIP_DEPS=1.
SKIP_DEPENDENCY_CHECK="${SERVER_MANAGER_SKIP_DEPS:-0}"

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-dependency-check|--no-dependency-check)
                SKIP_DEPENDENCY_CHECK=1
                ;;
        esac
        shift
    done
}

# Build the distribution-specific install hint for missing packages
install_hint() {
    local packages=("$@")

    if command -v apt-get &>/dev/null; then
        echo "sudo apt-get install ${packages[*]}"
    elif command -v pacman &>/dev/null; then
        # On Arch whiptail is shipped by the libnewt package
        local arch_packages=("${packages[@]//whiptail/libnewt}")
        echo "sudo pacman -S ${arch_packages[*]}"
    elif command -v dnf &>/dev/null; then
        echo "sudo dnf install ${packages[*]}"
    elif command -v zypper &>/dev/null; then
        echo "sudo zypper install ${packages[*]}"
    elif command -v apk &>/dev/null; then
        echo "sudo apk add ${packages[*]}"
    else
        echo "your distribution's package manager (${packages[*]})"
    fi
}

# Check dependencies
check_dependencies() {
    # Allow bypassing the check entirely
    if [[ "$SKIP_DEPENDENCY_CHECK" == "1" ]] || [[ -f "$SKIP_DEPS_FILE" ]]; then
        return 0
    fi

    local missing=()

    if ! command -v whiptail &>/dev/null; then
        missing+=("whiptail")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing dependencies: ${missing[*]}"
        echo "Install with: $(install_hint "${missing[@]}")"
        echo ""
        echo "To bypass this check, run with --skip-dependency-check"
        echo "or create the file: $SKIP_DEPS_FILE"
        exit 1
    fi
}

# Discover available modules
discover_modules() {
    local modules=()

    if [[ -d "$MODULES_DIR" ]]; then
        for module_file in "${MODULES_DIR}"/*.sh; do
            if [[ -f "$module_file" ]]; then
                local module_name
                module_name=$(basename "$module_file" .sh)
                modules+=("$module_name")
            fi
        done
    fi

    echo "${modules[@]}"
}

# Get module info
get_module_info() {
    local module_name="$1"
    local module_file="${MODULES_DIR}/${module_name}.sh"

    if [[ -f "$module_file" ]]; then
        # Source the module to get its metadata
        (
            source "$module_file"
            if declare -f module_info &>/dev/null; then
                module_info
            else
                echo "$module_name|No description available"
            fi
        )
    fi
}

# Run a module
run_module() {
    local module_name="$1"
    local module_file="${MODULES_DIR}/${module_name}.sh"

    if [[ -f "$module_file" ]]; then
        # Source libraries and module, then run
        (
            set +e  # Disable exit on error for module execution
            source "${LIB_DIR}/ui.sh"
            source "${LIB_DIR}/common.sh"
            source "$module_file"

            if declare -f module_main &>/dev/null; then
                module_main
            else
                ui_msgbox "Error" "Module '$module_name' has no main function"
            fi
        )
    else
        ui_msgbox "Error" "Module not found: $module_name"
    fi
}

# Main menu
main_menu() {
    while true; do
        local modules
        read -ra modules <<< "$(discover_modules)"

        if [[ ${#modules[@]} -eq 0 ]]; then
            ui_msgbox "No Modules" "No modules found in ${MODULES_DIR}"
            exit 1
        fi

        # Build menu items
        local menu_items=()
        for module in "${modules[@]}"; do
            local info
            info=$(get_module_info "$module")
            local name desc
            name=$(echo "$info" | cut -d'|' -f1)
            desc=$(echo "$info" | cut -d'|' -f2)
            menu_items+=("$module" "$desc")
        done

        # Show menu with Exit button instead of Cancel
        local choice
        choice=$(whiptail --title "Ubuntu Server Manager" \
            --cancel-button "Exit" \
            --menu "Select a module:" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
            "${menu_items[@]}" \
            3>&1 1>&2 2>&3) || break

        if [[ -n "$choice" ]]; then
            run_module "$choice"
        fi
    done
}

# Main entry point
main() {
    parse_args "$@"

    # Check for root privileges
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script requires administrative privileges."
        echo "Please run with sudo: sudo $0"
        exit 1
    fi

    check_dependencies

    # Create directories if they don't exist
    mkdir -p "$MODULES_DIR" "$LIB_DIR"

    main_menu

    clear
    echo "Goodbye!"
}

main "$@"
