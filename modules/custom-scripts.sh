#!/bin/bash
#
# Custom Scripts Module
# Install custom utility scripts for all users
#

# Module metadata
module_info() {
    echo "Custom Scripts|Install custom utility scripts"
}

# Get the directory where this script is located
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$MODULE_DIR/.." && pwd)"

# Path to custom scripts directory (relative to project root)
SCRIPTS_DIR="$PROJECT_ROOT/modules-files/custom-scripts"
INSTALL_DIR="/usr/local/bin"

# Get list of available scripts (excludes .description files)
get_available_scripts() {
    if [[ ! -d "$SCRIPTS_DIR" ]]; then
        return 1
    fi

    find "$SCRIPTS_DIR" -maxdepth 1 -type f ! -name ".*" ! -name "*.description" | sort
}

# Get description for a script
get_script_description() {
    local script_name="$1"
    local desc_file="$SCRIPTS_DIR/${script_name}.description"

    if [[ -f "$desc_file" ]]; then
        cat "$desc_file"
    else
        echo "No description available"
    fi
}

# Check if script is installed
is_installed() {
    local script_name="$1"
    [[ -f "$INSTALL_DIR/$script_name" ]]
}

# List available scripts
list_scripts() {
    if [[ ! -d "$SCRIPTS_DIR" ]]; then
        ui_msgbox "Error" "Scripts directory not found:\n$SCRIPTS_DIR"
        return 1
    fi

    local info=""
    info+="=== Available Custom Scripts ===\n\n"
    info+="Scripts location: $SCRIPTS_DIR\n"
    info+="Install location: $INSTALL_DIR\n\n"

    local count=0
    while IFS= read -r script_path; do
        [[ -z "$script_path" ]] && continue

        local script_name
        script_name=$(basename "$script_path")

        local status="Not installed"
        if is_installed "$script_name"; then
            status="INSTALLED"
        fi

        local description
        description=$(get_script_description "$script_name")

        info+="[$status] $script_name\n"
        info+="  Description: $description\n\n"
        ((count++))
    done < <(get_available_scripts)

    if [[ $count -eq 0 ]]; then
        info+="\nNo scripts found in $SCRIPTS_DIR\n"
    fi

    echo -e "$info" > /tmp/custom_scripts_list.txt
    ui_textbox "Custom Scripts" /tmp/custom_scripts_list.txt
    rm -f /tmp/custom_scripts_list.txt
}

# Install a script
install_script() {
    if ! require_root; then
        return 1
    fi

    if [[ ! -d "$SCRIPTS_DIR" ]]; then
        ui_msgbox "Error" "Scripts directory not found:\n$SCRIPTS_DIR"
        return 1
    fi

    # Build list of scripts
    local scripts_list=()
    while IFS= read -r script_path; do
        [[ -z "$script_path" ]] && continue

        local script_name
        script_name=$(basename "$script_path")

        local description
        description=$(get_script_description "$script_name")

        local status="off"
        if is_installed "$script_name"; then
            status="on"
        fi

        scripts_list+=("$script_name" "$description" "$status")
    done < <(get_available_scripts)

    if [[ ${#scripts_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No scripts available in:\n$SCRIPTS_DIR"
        return
    fi

    # Show selection menu
    local selected
    selected=$(ui_checklist "Install Scripts" "Select scripts to install to $INSTALL_DIR:" "${scripts_list[@]}") || return

    if [[ -z "$selected" ]]; then
        return
    fi

    # Install selected scripts
    local installed=0
    local failed=0
    local output=""

    for script in $selected; do
        script=$(echo "$script" | tr -d '"')

        if [[ ! -f "$SCRIPTS_DIR/$script" ]]; then
            output+="ERROR: Script not found: $script\n"
            ((failed++))
            continue
        fi

        # Copy script to install directory
        if cp "$SCRIPTS_DIR/$script" "$INSTALL_DIR/$script" 2>/dev/null; then
            # Make it executable
            chmod +x "$INSTALL_DIR/$script"
            output+="Installed: $script\n"
            log_info "Installed custom script: $script"
            ((installed++))
        else
            output+="FAILED: $script\n"
            log_error "Failed to install custom script: $script"
            ((failed++))
        fi
    done

    # Show results
    local msg="Installation complete:\n\n"
    msg+="Installed: $installed\n"
    msg+="Failed: $failed\n\n"
    msg+="$output"

    ui_msgbox "Installation Results" "$msg"
}

# Uninstall a script
uninstall_script() {
    if ! require_root; then
        return 1
    fi

    # Build list of installed scripts
    local scripts_list=()
    while IFS= read -r script_path; do
        [[ -z "$script_path" ]] && continue

        local script_name
        script_name=$(basename "$script_path")

        if is_installed "$script_name"; then
            local description
            description=$(get_script_description "$script_name")
            scripts_list+=("$script_name" "$description" "on")
        fi
    done < <(get_available_scripts)

    if [[ ${#scripts_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No custom scripts are currently installed"
        return
    fi

    # Show selection menu
    local selected
    selected=$(ui_checklist "Uninstall Scripts" "Select scripts to uninstall from $INSTALL_DIR:" "${scripts_list[@]}") || return

    if [[ -z "$selected" ]]; then
        return
    fi

    # Confirm removal
    if ! ui_yesno "Confirm" "Uninstall selected scripts?\n\nThis will remove them from $INSTALL_DIR"; then
        return
    fi

    # Uninstall selected scripts
    local removed=0
    local failed=0
    local output=""

    for script in $selected; do
        script=$(echo "$script" | tr -d '"')

        if rm -f "$INSTALL_DIR/$script" 2>/dev/null; then
            output+="Removed: $script\n"
            log_info "Uninstalled custom script: $script"
            ((removed++))
        else
            output+="FAILED: $script\n"
            log_error "Failed to uninstall custom script: $script"
            ((failed++))
        fi
    done

    # Show results
    local msg="Uninstallation complete:\n\n"
    msg+="Removed: $removed\n"
    msg+="Failed: $failed\n\n"
    msg+="$output"

    ui_msgbox "Uninstallation Results" "$msg"
}

# Update all installed scripts
update_all_scripts() {
    if ! require_root; then
        return 1
    fi

    if [[ ! -d "$SCRIPTS_DIR" ]]; then
        ui_msgbox "Error" "Scripts directory not found:\n$SCRIPTS_DIR"
        return 1
    fi

    # Find installed scripts
    local installed_scripts=()
    while IFS= read -r script_path; do
        [[ -z "$script_path" ]] && continue

        local script_name
        script_name=$(basename "$script_path")

        if is_installed "$script_name"; then
            installed_scripts+=("$script_name")
        fi
    done < <(get_available_scripts)

    if [[ ${#installed_scripts[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No custom scripts are currently installed"
        return
    fi

    if ! ui_yesno "Confirm" "Update all ${#installed_scripts[@]} installed script(s) from source?\n\nThis will overwrite the installed versions in $INSTALL_DIR"; then
        return
    fi

    local updated=0
    local failed=0
    local output=""

    for script_name in "${installed_scripts[@]}"; do
        if cp "$SCRIPTS_DIR/$script_name" "$INSTALL_DIR/$script_name" 2>/dev/null; then
            chmod +x "$INSTALL_DIR/$script_name"
            output+="Updated: $script_name\n"
            log_info "Updated custom script: $script_name"
            ((updated++))
        else
            output+="FAILED: $script_name\n"
            log_error "Failed to update custom script: $script_name"
            ((failed++))
        fi
    done

    local msg="Update complete:\n\n"
    msg+="Updated: $updated\n"
    msg+="Failed: $failed\n\n"
    msg+="$output"

    ui_msgbox "Update Results" "$msg"
}

# View script content
view_script() {
    if [[ ! -d "$SCRIPTS_DIR" ]]; then
        ui_msgbox "Error" "Scripts directory not found:\n$SCRIPTS_DIR"
        return 1
    fi

    # Build list of scripts
    local scripts_list=()
    while IFS= read -r script_path; do
        [[ -z "$script_path" ]] && continue

        local script_name
        script_name=$(basename "$script_path")

        local description
        description=$(get_script_description "$script_name")

        scripts_list+=("$script_name" "$description")
    done < <(get_available_scripts)

    if [[ ${#scripts_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No scripts available"
        return
    fi

    # Show selection menu
    local script
    script=$(ui_menu "View Script" "Select script to view:" "${scripts_list[@]}") || return

    # Display script content
    if [[ -f "$SCRIPTS_DIR/$script" ]]; then
        ui_textbox "Script: $script" "$SCRIPTS_DIR/$script"
    else
        ui_msgbox "Error" "Script not found: $script"
    fi
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "Custom Scripts" "Select operation:" \
            "list" "List available scripts" \
            "install" "Install scripts" \
            "update" "Update all installed scripts" \
            "uninstall" "Uninstall scripts" \
            "view" "View script content") || break

        case "$choice" in
            list)      list_scripts ;;
            install)   install_script ;;
            update)    update_all_scripts ;;
            uninstall) uninstall_script ;;
            view)      view_script ;;
        esac
    done
}
