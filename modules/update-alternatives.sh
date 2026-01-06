#!/bin/bash
#
# Update Alternatives Module
# Manage system alternatives using the update-alternatives command
#

# Module metadata
module_info() {
    echo "Update Alternatives|Manage system alternatives (editor, pager, etc.)"
}

# Configure an alternative using native interface
configure_alternative() {
    local alt_name="$1"

    if [[ -z "$alt_name" ]]; then
        ui_msgbox "Error" "Alternative name not specified"
        return 1
    fi

    # Check root access
    if ! require_root; then
        return 1
    fi

    # Check if alternative exists and count options
    local count
    count=$(update-alternatives --list "$alt_name" 2>/dev/null | wc -l)

    if [[ $? -ne 0 ]] || [[ $count -eq 0 ]]; then
        ui_msgbox "Error" "Alternative '$alt_name' not found."
        return 1
    fi

    if [[ $count -eq 1 ]]; then
        ui_msgbox "Info" "Alternative '$alt_name' has only one option.\n\nNo configuration needed."
        return 0
    fi

    # Get current selection before making changes
    local before_path
    before_path=$(update-alternatives --query "$alt_name" 2>/dev/null | grep "^Value:" | cut -d' ' -f2-)

    # If --query not available, try --display
    if [[ -z "$before_path" ]]; then
        before_path=$(update-alternatives --display "$alt_name" 2>/dev/null | grep "currently points to" | sed 's/.*currently points to //')
    fi

    # Set up trap to catch CTRL+C and prevent script exit
    local interrupted=0
    trap 'interrupted=1' INT

    # Run native config
    clear
    update-alternatives --config "$alt_name"
    local result=$?

    # Remove the trap
    trap - INT

    # Check if user interrupted with CTRL+C
    if [[ $interrupted -eq 1 ]] || [[ $result -eq 130 ]]; then
        log_info "User aborted configuration for alternative: $alt_name"
        ui_msgbox "Cancelled" "Configuration was cancelled by user.\n\nAlternative: $alt_name"
        return 0
    fi

    if [[ $result -eq 0 ]]; then
        # Get new selection after changes
        local after_path
        after_path=$(update-alternatives --query "$alt_name" 2>/dev/null | grep "^Value:" | cut -d' ' -f2-)

        # If --query not available, try --display
        if [[ -z "$after_path" ]]; then
            after_path=$(update-alternatives --display "$alt_name" 2>/dev/null | grep "currently points to" | sed 's/.*currently points to //')
        fi

        log_info "User configured alternative: $alt_name (from: $before_path to: $after_path)"

        # Show what changed
        local msg="Alternative '$alt_name' configured successfully.\n\n"
        if [[ "$before_path" != "$after_path" ]]; then
            msg+="Changed from:\n  $before_path\n\nChanged to:\n  $after_path"
        else
            msg+="No change made (same option selected).\n\nCurrent: $after_path"
        fi

        ui_msgbox "Success" "$msg"
    else
        log_error "Failed to configure alternative: $alt_name (exit code: $result)"
        ui_msgbox "Error" "Configuration failed for '$alt_name'.\n\nExit code: $result\nCheck the logs for details."
    fi
}

# List all alternatives and allow selection
list_alternatives() {
    while true; do
        # Build menu of all alternatives
        local menu_items=()

        while IFS= read -r line; do
            # Parse: name, mode, path (whitespace separated)
            local name mode path
            read -r name mode path <<< "$line"

            # Skip empty lines
            [[ -z "$name" ]] && continue

            # Truncate path for display
            local display_path="${path:0:60}"
            [[ ${#path} -gt 60 ]] && display_path="${display_path}..."

            # Add to menu with mode indicator
            menu_items+=("$name" "[$mode] $display_path")
        done < <(update-alternatives --get-selections 2>/dev/null | sort)

        # Check if any alternatives found
        if [[ ${#menu_items[@]} -eq 0 ]]; then
            ui_msgbox "Info" "No alternatives found on this system."
            return 0
        fi

        # Calculate count (divide by 2 since menu_items has tag + description pairs)
        local count=$((${#menu_items[@]} / 2))

        # Show selection menu
        local selected
        selected=$(ui_menu "System Alternatives" \
            "Select alternative to configure ($count total):" \
            "${menu_items[@]}") || break

        # Immediately configure selected alternative
        configure_alternative "$selected"
    done
}

# Main module function
module_main() {
    list_alternatives
}
