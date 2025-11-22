#!/bin/bash
#
# UI Helper Library - Whiptail wrapper functions
# Provides a consistent API for building TUI interfaces
# Uses whiptail for better compatibility with non-interactive SSH sessions
#

# Dialog settings - doubled for better visibility
DIALOG_HEIGHT=40
DIALOG_WIDTH=140
DIALOG_MENU_HEIGHT=24

# Temporary file for dialog output
DIALOG_TEMPFILE=$(mktemp)
trap "rm -f $DIALOG_TEMPFILE" EXIT

# Ensure TERM is set for non-interactive sessions
export NEWT_COLORS='root=,black'
if [[ -z "$TERM" ]] || [[ "$TERM" == "dumb" ]]; then
    export TERM=xterm
fi

#=============================================================================
# Basic Dialog Functions
#=============================================================================

# Show a message box
# Usage: ui_msgbox "Title" "Message"
ui_msgbox() {
    local title="$1"
    local message="$2"
    whiptail --title "$title" --msgbox "$message" $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Show an info box (non-blocking)
# Usage: ui_infobox "Title" "Message"
# Note: whiptail's infobox requires --fb flag and clears immediately
ui_infobox() {
    local title="$1"
    local message="$2"
    # whiptail infobox behavior differs from dialog; use msgbox-like display briefly
    echo -ne "\033[2J\033[H"  # Clear screen
    whiptail --title "$title" --infobox "$message" 8 $DIALOG_WIDTH
}

# Show a yes/no dialog
# Usage: if ui_yesno "Title" "Question"; then echo "Yes"; fi
ui_yesno() {
    local title="$1"
    local message="$2"
    whiptail --title "$title" --yesno "$message" $DIALOG_HEIGHT $DIALOG_WIDTH
}

#=============================================================================
# Input Functions
#=============================================================================

# Show a text input box
# Usage: result=$(ui_inputbox "Title" "Prompt" "default_value")
ui_inputbox() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"

    whiptail --title "$title" \
        --inputbox "$prompt" $DIALOG_HEIGHT $DIALOG_WIDTH "$default" \
        3>&1 1>&2 2>&3

    return $?
}

# Show a password input box
# Usage: result=$(ui_passwordbox "Title" "Prompt")
ui_passwordbox() {
    local title="$1"
    local prompt="$2"

    whiptail --title "$title" \
        --passwordbox "$prompt" $DIALOG_HEIGHT $DIALOG_WIDTH \
        3>&1 1>&2 2>&3

    return $?
}

#=============================================================================
# Selection Functions
#=============================================================================

# Show a menu
# Usage: choice=$(ui_menu "Title" "Prompt" "tag1" "desc1" "tag2" "desc2" ...)
ui_menu() {
    local title="$1"
    local prompt="$2"
    shift 2

    whiptail --title "$title" \
        --menu "$prompt" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
        "$@" \
        3>&1 1>&2 2>&3

    return $?
}

# Show a checklist (multiple selection)
# Usage: choices=$(ui_checklist "Title" "Prompt" "tag1" "desc1" "on/off" ...)
ui_checklist() {
    local title="$1"
    local prompt="$2"
    shift 2

    whiptail --title "$title" \
        --checklist "$prompt" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
        "$@" \
        3>&1 1>&2 2>&3

    return $?
}

# Show a radiolist (single selection from multiple)
# Usage: choice=$(ui_radiolist "Title" "Prompt" "tag1" "desc1" "on/off" ...)
ui_radiolist() {
    local title="$1"
    local prompt="$2"
    shift 2

    whiptail --title "$title" \
        --radiolist "$prompt" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
        "$@" \
        3>&1 1>&2 2>&3

    return $?
}

#=============================================================================
# File/Directory Selection
#=============================================================================

# Show a file selection dialog
# Usage: file=$(ui_fselect "/starting/path")
# Note: whiptail doesn't have fselect, using inputbox as fallback
ui_fselect() {
    local start_path="${1:-$HOME}"

    whiptail --title "Select File" \
        --inputbox "Enter file path:" $DIALOG_HEIGHT $DIALOG_WIDTH "$start_path" \
        3>&1 1>&2 2>&3

    return $?
}

# Show a directory selection dialog
# Usage: dir=$(ui_dselect "/starting/path")
# Note: whiptail doesn't have dselect, using inputbox as fallback
ui_dselect() {
    local start_path="${1:-$HOME}"

    whiptail --title "Select Directory" \
        --inputbox "Enter directory path:" $DIALOG_HEIGHT $DIALOG_WIDTH "$start_path" \
        3>&1 1>&2 2>&3

    return $?
}

#=============================================================================
# Date/Time Functions
#=============================================================================

# Show a calendar dialog
# Usage: date=$(ui_calendar "Title" day month year)
# Note: whiptail doesn't have calendar, using inputbox as fallback
ui_calendar() {
    local title="$1"
    local day="${2:-$(date +%d)}"
    local month="${3:-$(date +%m)}"
    local year="${4:-$(date +%Y)}"
    local default_date="$day/$month/$year"

    whiptail --title "$title" \
        --inputbox "Enter date (DD/MM/YYYY):" $DIALOG_HEIGHT $DIALOG_WIDTH "$default_date" \
        3>&1 1>&2 2>&3

    return $?
}

# Show a time selection dialog
# Usage: time=$(ui_timebox "Title" hour minute second)
# Note: whiptail doesn't have timebox, using inputbox as fallback
ui_timebox() {
    local title="$1"
    local hour="${2:-$(date +%H)}"
    local minute="${3:-$(date +%M)}"
    local second="${4:-$(date +%S)}"
    local default_time="$hour:$minute:$second"

    whiptail --title "$title" \
        --inputbox "Enter time (HH:MM:SS):" $DIALOG_HEIGHT $DIALOG_WIDTH "$default_time" \
        3>&1 1>&2 2>&3

    return $?
}

#=============================================================================
# Form Functions
#=============================================================================

# Show a form with multiple fields
# Usage: ui_form "Title" "Label1" y1 x1 "Value1" y1 x1 len1 maxlen1 ...
# Returns values separated by newlines
# Note: whiptail doesn't support forms, using multiple inputboxes as fallback
ui_form() {
    local title="$1"
    shift

    local results=""
    local label value

    # Parse arguments in groups of 8 (label y x value y x len maxlen)
    while [[ $# -ge 8 ]]; do
        label="$1"
        value="$4"

        local input
        input=$(whiptail --title "$title" \
            --inputbox "$label" $DIALOG_HEIGHT $DIALOG_WIDTH "$value" \
            3>&1 1>&2 2>&3) || return 1

        if [[ -n "$results" ]]; then
            results="$results"$'\n'"$input"
        else
            results="$input"
        fi

        shift 8
    done

    echo "$results"
    return 0
}

# Show a mixed form (with password fields)
# Usage: ui_mixedform "Title" "Label1" y1 x1 "Value1" y1 x1 len1 maxlen1 type1 ...
# type: 0=regular, 1=hidden, 2=readonly
# Note: whiptail doesn't support mixedform, using multiple inputs as fallback
ui_mixedform() {
    local title="$1"
    shift

    local results=""
    local label value field_type

    # Parse arguments in groups of 9 (label y x value y x len maxlen type)
    while [[ $# -ge 9 ]]; do
        label="$1"
        value="$4"
        field_type="$9"

        local input
        if [[ "$field_type" == "1" ]]; then
            # Password field
            input=$(whiptail --title "$title" \
                --passwordbox "$label" $DIALOG_HEIGHT $DIALOG_WIDTH \
                3>&1 1>&2 2>&3) || return 1
        else
            # Regular field
            input=$(whiptail --title "$title" \
                --inputbox "$label" $DIALOG_HEIGHT $DIALOG_WIDTH "$value" \
                3>&1 1>&2 2>&3) || return 1
        fi

        if [[ -n "$results" ]]; then
            results="$results"$'\n'"$input"
        else
            results="$input"
        fi

        shift 9
    done

    echo "$results"
    return 0
}

#=============================================================================
# Progress Functions
#=============================================================================

# Show a gauge (progress bar)
# Usage: echo "50" | ui_gauge "Title" "Processing..."
# Or pipe percentage updates
ui_gauge() {
    local title="$1"
    local text="$2"
    local initial="${3:-0}"

    whiptail --title "$title" \
        --gauge "$text" 8 $DIALOG_WIDTH "$initial"
}

# Show a progress box for command output
# Usage: command | ui_progressbox "Title"
# Note: whiptail doesn't have progressbox, showing output then msgbox
ui_progressbox() {
    local title="$1"
    local output
    output=$(cat)

    # Show output in a scrollable msgbox
    whiptail --title "$title" --scrolltext \
        --msgbox "$output" $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Show a program box (run command and display output)
# Usage: ui_programbox "Title" command args...
# Note: whiptail doesn't have programbox, using msgbox with output
ui_programbox() {
    local title="$1"
    shift

    local output
    output=$("$@" 2>&1)

    whiptail --title "$title" --scrolltext \
        --msgbox "$output" $DIALOG_HEIGHT $DIALOG_WIDTH
}

#=============================================================================
# Text Display Functions
#=============================================================================

# Show a text box (display file contents)
# Usage: ui_textbox "Title" "/path/to/file"
ui_textbox() {
    local title="$1"
    local file="$2"

    whiptail --title "$title" --scrolltext \
        --textbox "$file" $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Show an editable text box
# Usage: result=$(ui_editbox "Title" "/path/to/file")
# Note: whiptail doesn't have editbox, showing content in inputbox
ui_editbox() {
    local title="$1"
    local file="$2"
    local content
    content=$(cat "$file")

    # Note: This is a limited fallback - only works for small files
    whiptail --title "$title" \
        --inputbox "Edit content:" $DIALOG_HEIGHT $DIALOG_WIDTH "$content" \
        3>&1 1>&2 2>&3

    return $?
}

#=============================================================================
# Custom Button Functions
#=============================================================================

# Show a menu with custom buttons
# Usage: ui_menu_with_buttons "Title" "Ok" "Cancel" "Help" "Prompt" items...
# Note: whiptail has limited button customization
ui_menu_with_buttons() {
    local title="$1"
    local ok_label="$2"
    local cancel_label="$3"
    local help_label="$4"
    local prompt="$5"
    shift 5

    whiptail --title "$title" \
        --ok-button "$ok_label" \
        --cancel-button "$cancel_label" \
        --menu "$prompt" $DIALOG_HEIGHT $DIALOG_WIDTH $DIALOG_MENU_HEIGHT \
        "$@" \
        3>&1 1>&2 2>&3

    return $?
}

# Show dialog with extra button
# Usage: ui_with_extra_button "Title" "Extra Label" command args...
# Note: whiptail doesn't support extra buttons, ignoring extra button
ui_with_extra_button() {
    local extra_label="$1"
    shift

    # whiptail doesn't support extra buttons, run without it
    whiptail "$@" 3>&1 1>&2 2>&3

    return $?
}

#=============================================================================
# Utility Functions
#=============================================================================

# Clear the screen
ui_clear() {
    clear
}

# Show command output in a scrollable box
# Usage: ui_show_output "Title" "command output here"
ui_show_output() {
    local title="$1"
    local output="$2"

    whiptail --title "$title" --scrolltext \
        --msgbox "$output" $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Run a command and show its output
# Usage: ui_run_command "Title" command args...
ui_run_command() {
    local title="$1"
    shift

    local output
    output=$("$@" 2>&1)
    local status=$?

    if [[ -n "$output" ]]; then
        ui_show_output "$title" "$output"
    fi

    return $status
}

# Run command with progress
# Usage: ui_run_with_progress "Title" "Message" command args...
ui_run_with_progress() {
    local title="$1"
    local message="$2"
    shift 2

    (
        echo "0"
        "$@" 2>&1
        echo "100"
    ) | whiptail --title "$title" --gauge "$message" 8 $DIALOG_WIDTH 0
}
