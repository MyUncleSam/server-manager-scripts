#!/bin/bash
#
# Cron Module
# Manage cron jobs and schedules
#

# Module metadata
module_info() {
    echo "Cron Jobs|Manage cron jobs and schedules"
}

# Get the directory where this script is located
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$MODULE_DIR/.." && pwd)"

# Path to cron files directory (relative to project root)
CRONFILES_DIR="$PROJECT_ROOT/modules-files/cron"
INSTALL_DIR="/etc/cron.d"
FILE_PREFIX="servermgr-"

#=============================================================================
# User Crontab Management Functions
#=============================================================================

# Get all users with crontabs
get_all_users_with_crontabs() {
    local users_with_crontabs=""

    # Check all users in /etc/passwd
    while IFS=: read -r username _ uid _; do
        # Check if user has a crontab
        if crontab -l -u "$username" 2>/dev/null | grep -v '^#' | grep -v '^$' >/dev/null; then
            users_with_crontabs+="$username "
        fi
    done < /etc/passwd

    echo "$users_with_crontabs"
}

# List users with cron jobs
list_users_with_crontabs() {
    local info="=== Users with Cron Jobs ===\n\n"
    local users
    users=$(get_all_users_with_crontabs)

    if [[ -z "$users" ]]; then
        info+="No users have crontabs configured.\n"
    else
        for user in $users; do
            local count
            count=$(crontab -l -u "$user" 2>/dev/null | grep -v '^#' | grep -v '^$' | wc -l)
            info+="$user - $count job(s)\n"
        done
    fi

    echo -e "$info" > /tmp/cron_users.txt
    ui_textbox "Cron Users" /tmp/cron_users.txt
    rm -f /tmp/cron_users.txt
}

# View all crontabs at once
view_all_crontabs() {
    local tmpfile="/tmp/all_crontabs.txt"
    local users
    users=$(get_all_users_with_crontabs)

    if [[ -z "$users" ]]; then
        ui_msgbox "Info" "No crontabs found on this system"
        return
    fi

    {
        for user in $users; do
            echo "========================================="
            echo "User: $user"
            echo "========================================="
            crontab -l -u "$user" 2>/dev/null
            echo ""
            echo ""
        done
    } > "$tmpfile"

    # Try syntax highlighting if bat is available
    if command_exists bat; then
        bat --style=plain --language=crontab "$tmpfile" > "${tmpfile}.highlighted" 2>/dev/null
        if [[ -f "${tmpfile}.highlighted" ]]; then
            ui_textbox "All Crontabs" "${tmpfile}.highlighted"
            rm -f "${tmpfile}.highlighted"
        else
            ui_textbox "All Crontabs" "$tmpfile"
        fi
    else
        ui_textbox "All Crontabs" "$tmpfile"
    fi

    rm -f "$tmpfile"
}

# View a specific user's crontab
view_user_crontab() {
    local users
    users=$(get_all_users_with_crontabs)

    # Check if any users have crontabs
    if [[ -z "$users" ]]; then
        ui_msgbox "Info" "No users have crontabs configured."
        return
    fi

    # Build menu list (only users with crontabs)
    local user_list=()
    for user in $users; do
        local count
        count=$(crontab -l -u "$user" 2>/dev/null | grep -v '^#' | grep -v '^$' | wc -l)
        user_list+=("$user" "$count job(s)")
    done

    local user
    user=$(ui_menu "View Crontab" "Select user:" "${user_list[@]}") || return

    local tmpfile="/tmp/crontab_${user}.txt"
    crontab -l -u "$user" 2>/dev/null > "$tmpfile"

    # Try syntax highlighting if bat is available
    if command_exists bat; then
        bat --style=plain --language=crontab "$tmpfile" > "${tmpfile}.highlighted" 2>/dev/null
        if [[ -f "${tmpfile}.highlighted" ]]; then
            ui_textbox "Crontab: $user" "${tmpfile}.highlighted"
            rm -f "${tmpfile}.highlighted"
        else
            ui_textbox "Crontab: $user" "$tmpfile"
        fi
    else
        ui_textbox "Crontab: $user" "$tmpfile"
    fi

    rm -f "$tmpfile"
}

# Edit a user's crontab
edit_user_crontab() {
    if ! require_root; then
        return 1
    fi

    local users
    users=$(get_all_users_with_crontabs)
    local all_users
    all_users=$(awk -F: '{print $1}' /etc/passwd | sort)

    # Build menu list
    local user_list=()
    for user in $all_users; do
        if echo "$users" | grep -q -w "$user"; then
            user_list+=("$user" "Has crontab")
        else
            user_list+=("$user" "No crontab")
        fi
    done

    local user
    user=$(ui_menu "Edit Crontab" "Select user:" "${user_list[@]}") || return

    # Run crontab -e directly (uses system default editor)
    # Capture output to show result to user
    local result_file="/tmp/crontab_edit_result.$$"
    clear
    crontab -e -u "$user" 2>"$result_file"
    local exit_code=$?

    # Read the result message
    local result_msg=""
    if [[ -f "$result_file" && -s "$result_file" ]]; then
        result_msg=$(cat "$result_file")
        rm -f "$result_file"
    fi

    # Show result to user
    if [[ -n "$result_msg" ]]; then
        ui_msgbox "Crontab Edit Result" "User: $user\n\n$result_msg"
        log_info "Edited crontab for user: $user - $result_msg"
    else
        log_info "Edited crontab for user: $user"
    fi
}

#=============================================================================
# System Cron File Management Functions
#=============================================================================

# Get list of available cron files (excludes .description files)
get_available_cronfiles() {
    if [[ ! -d "$CRONFILES_DIR" ]]; then
        return 1
    fi

    find "$CRONFILES_DIR" -maxdepth 1 -type f ! -name ".*" ! -name "*.description" | sort
}

# Get description for a cron file
get_cronfile_description() {
    local cronfile_name="$1"
    local desc_file="$CRONFILES_DIR/${cronfile_name}.description"

    if [[ -f "$desc_file" ]]; then
        cat "$desc_file"
    else
        echo "No description available"
    fi
}

# Check if cron file is installed
is_cronfile_installed() {
    local cronfile_name="$1"
    [[ -f "$INSTALL_DIR/${FILE_PREFIX}$cronfile_name" ]]
}

# Validate cron file syntax
validate_cronfile() {
    local file="$1"

    # Check file exists and is readable
    [[ ! -f "$file" ]] && return 1

    # Basic checks:
    # 1. Must have at least one non-comment, non-empty line
    # 2. Lines should have at least 7 fields (minute hour day month dow user command)

    local valid_lines=0
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Check for PATH or other variable assignments
        [[ "$line" =~ ^[A-Z_]+= ]] && continue

        # Count fields (should be 7+)
        local field_count
        field_count=$(echo "$line" | awk '{print NF}')
        if [[ $field_count -lt 7 ]]; then
            log_warn "Cron file validation: line has only $field_count fields: $line"
            return 1
        fi

        ((valid_lines++))
    done < "$file"

    # Must have at least one valid cron entry
    [[ $valid_lines -gt 0 ]]
}

# List available cron files
list_cronfiles() {
    if [[ ! -d "$CRONFILES_DIR" ]]; then
        ui_msgbox "Error" "Cron files directory not found:\n$CRONFILES_DIR"
        return 1
    fi

    local info=""
    info+="=== Available System Cron Files ===\n\n"
    info+="Files location: $CRONFILES_DIR\n"
    info+="Install location: $INSTALL_DIR\n\n"

    local count=0
    while IFS= read -r cronfile_path; do
        [[ -z "$cronfile_path" ]] && continue

        local cronfile_name
        cronfile_name=$(basename "$cronfile_path")

        local status="Not installed"
        if is_cronfile_installed "$cronfile_name"; then
            status="INSTALLED"
        fi

        local description
        description=$(get_cronfile_description "$cronfile_name")

        info+="[$status] $cronfile_name\n"
        info+="  Description: $description\n\n"
        ((count++))
    done < <(get_available_cronfiles)

    if [[ $count -eq 0 ]]; then
        info+="\nNo cron files found in $CRONFILES_DIR\n"
    fi

    echo -e "$info" > /tmp/cronfiles_list.txt
    ui_textbox "System Cron Files" /tmp/cronfiles_list.txt
    rm -f /tmp/cronfiles_list.txt
}

# Install cron file(s)
install_cronfile() {
    if ! require_root; then
        return 1
    fi

    if [[ ! -d "$CRONFILES_DIR" ]]; then
        ui_msgbox "Error" "Cron files directory not found:\n$CRONFILES_DIR"
        return 1
    fi

    # Build list of cron files (exclude already installed)
    local cronfiles_list=()
    while IFS= read -r cronfile_path; do
        [[ -z "$cronfile_path" ]] && continue

        local cronfile_name
        cronfile_name=$(basename "$cronfile_path")

        # Skip already installed files
        if is_cronfile_installed "$cronfile_name"; then
            continue
        fi

        local description
        description=$(get_cronfile_description "$cronfile_name")

        cronfiles_list+=("$cronfile_name" "$description" "off")
    done < <(get_available_cronfiles)

    if [[ ${#cronfiles_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No cron files available to install.\n\nAll available cron files are already installed."
        return
    fi

    # Show selection menu
    local selected
    selected=$(ui_checklist "Install Cron Jobs" "Select cron jobs to install to $INSTALL_DIR:" "${cronfiles_list[@]}") || return

    if [[ -z "$selected" ]]; then
        return
    fi

    # Build preview content and show with yes/no approval
    local preview_content="=== Cron Jobs to be Installed ===\n\n"
    preview_content+="Installation location: $INSTALL_DIR\n\n"
    preview_content+="Proceed with installation?\n\n"

    for cronfile in $selected; do
        cronfile=$(echo "$cronfile" | tr -d '"')

        if [[ -f "$CRONFILES_DIR/$cronfile" ]]; then
            preview_content+="=========================================\n"
            preview_content+="File: ${FILE_PREFIX}$cronfile\n"
            preview_content+="=========================================\n"
            preview_content+="$(cat "$CRONFILES_DIR/$cronfile")\n"
            preview_content+="\n"
        fi
    done

    # Show preview with yes/no buttons
    if ! ui_yesno "Review and Approve Cron Jobs" "$preview_content"; then
        return
    fi

    # Install selected cron files
    local installed=0
    local failed=0
    local output=""

    for cronfile in $selected; do
        cronfile=$(echo "$cronfile" | tr -d '"')

        if [[ ! -f "$CRONFILES_DIR/$cronfile" ]]; then
            output+="ERROR: File not found: $cronfile\n"
            ((failed++))
            continue
        fi

        # Validate syntax
        if ! validate_cronfile "$CRONFILES_DIR/$cronfile"; then
            output+="FAILED: Invalid syntax: $cronfile\n"
            ((failed++))
            continue
        fi

        # Copy to /etc/cron.d/ with prefix
        if cp "$CRONFILES_DIR/$cronfile" "$INSTALL_DIR/${FILE_PREFIX}$cronfile" 2>/dev/null; then
            chmod 644 "$INSTALL_DIR/${FILE_PREFIX}$cronfile"
            output+="Installed: $cronfile\n"
            log_info "Installed cron job: $cronfile"
            ((installed++))
        else
            output+="FAILED: $cronfile\n"
            log_error "Failed to install cron job: $cronfile"
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

# Uninstall cron file(s)
uninstall_cronfile() {
    if ! require_root; then
        return 1
    fi

    # Build list of installed cron files
    local cronfiles_list=()
    while IFS= read -r cronfile_path; do
        [[ -z "$cronfile_path" ]] && continue

        local cronfile_name
        cronfile_name=$(basename "$cronfile_path")

        if is_cronfile_installed "$cronfile_name"; then
            local description
            description=$(get_cronfile_description "$cronfile_name")
            cronfiles_list+=("$cronfile_name" "$description" "on")
        fi
    done < <(get_available_cronfiles)

    if [[ ${#cronfiles_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No system cron files are currently installed"
        return
    fi

    # Show selection menu
    local selected
    selected=$(ui_checklist "Uninstall Cron Jobs" "Select cron jobs to uninstall from $INSTALL_DIR:" "${cronfiles_list[@]}") || return

    if [[ -z "$selected" ]]; then
        return
    fi

    # Confirm removal
    if ! ui_yesno "Confirm" "Uninstall selected cron jobs?\n\nThis will remove them from $INSTALL_DIR"; then
        return
    fi

    # Uninstall selected cron files
    local removed=0
    local failed=0
    local output=""

    for cronfile in $selected; do
        cronfile=$(echo "$cronfile" | tr -d '"')

        if rm -f "$INSTALL_DIR/${FILE_PREFIX}$cronfile" 2>/dev/null; then
            output+="Removed: $cronfile\n"
            log_info "Uninstalled cron job: $cronfile"
            ((removed++))
        else
            output+="FAILED: $cronfile\n"
            log_error "Failed to uninstall cron job: $cronfile"
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

# View cron file content
view_cronfile() {
    if [[ ! -d "$CRONFILES_DIR" ]]; then
        ui_msgbox "Error" "Cron files directory not found:\n$CRONFILES_DIR"
        return 1
    fi

    # Build list of cron files
    local cronfiles_list=()
    while IFS= read -r cronfile_path; do
        [[ -z "$cronfile_path" ]] && continue

        local cronfile_name
        cronfile_name=$(basename "$cronfile_path")

        local description
        description=$(get_cronfile_description "$cronfile_name")

        cronfiles_list+=("$cronfile_name" "$description")
    done < <(get_available_cronfiles)

    if [[ ${#cronfiles_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No cron files available"
        return
    fi

    # Show selection menu
    local cronfile
    cronfile=$(ui_menu "View Cron File" "Select cron file to view:" "${cronfiles_list[@]}") || return

    # Display cron file content
    if [[ -f "$CRONFILES_DIR/$cronfile" ]]; then
        ui_textbox "Cron File: $cronfile" "$CRONFILES_DIR/$cronfile"
    else
        ui_msgbox "Error" "Cron file not found: $cronfile"
    fi
}

# Edit system cron file
edit_system_cronfile() {
    if ! require_root; then
        return 1
    fi

    # System cron directories
    local cron_dirs=(
        "/etc/cron.d"
        "/etc/cron.daily"
        "/etc/cron.hourly"
        "/etc/cron.monthly"
        "/etc/cron.weekly"
    )

    # Add cron.yearly if it exists (not on all systems)
    if [[ -d "/etc/cron.yearly" ]]; then
        cron_dirs+=("/etc/cron.yearly")
    fi

    # Build list of all cron files
    local cronfiles_list=()
    for dir in "${cron_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            continue
        fi

        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            # Skip directories, only list files
            [[ -d "$file" ]] && continue

            local filename=$(basename "$file")
            local dirname=$(basename "$dir")
            cronfiles_list+=("$file" "$dirname/$filename")
        done < <(find "$dir" -maxdepth 1 -type f ! -name ".*" | sort)
    done

    if [[ ${#cronfiles_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No system cron files found"
        return
    fi

    # Show selection menu
    local selected_file
    selected_file=$(ui_menu "Edit System Cron File" "Select file to edit:" "${cronfiles_list[@]}") || return

    # Edit the file using system editor
    clear
    editor "$selected_file"

    log_info "Edited system cron file: $selected_file"
}

#=============================================================================
# Main Module Function
#=============================================================================

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "Cron Jobs" "Select operation:" \
            "view-user" "View user crontab" \
            "edit-user" "Edit user crontab" \
            "edit-system" "Edit system cron file" \
            "install-system" "Install system cron files" \
            "uninstall-system" "Uninstall system cron files") || break

        case "$choice" in
            view-user)        view_user_crontab ;;
            edit-user)        edit_user_crontab ;;
            edit-system)      edit_system_cronfile ;;
            install-system)   install_cronfile ;;
            uninstall-system) uninstall_cronfile ;;
        esac
    done
}
