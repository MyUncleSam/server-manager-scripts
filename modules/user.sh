#!/bin/bash
#
# User Management Module
# Manage system users: add, modify, delete, and view user information
#

# Module metadata
module_info() {
    echo "User Management|Manage system users and groups"
}

# Add a new user
add_user() {
    if ! require_root; then
        return 1
    fi

    # Get username
    local username
    username=$(ui_inputbox "Add User" "Enter username:") || return

    if [[ -z "$username" ]]; then
        ui_msgbox "Error" "Username cannot be empty"
        return 1
    fi

    if ! validate_username "$username"; then
        ui_msgbox "Error" "Invalid username format.\nMust start with lowercase letter or underscore,\ncontain only lowercase letters, digits, underscores, or hyphens."
        return 1
    fi

    if user_exists "$username"; then
        ui_msgbox "Error" "User '$username' already exists"
        return 1
    fi

    # Get full name
    local fullname
    fullname=$(ui_inputbox "Add User" "Enter full name (optional):") || return

    # Get password
    local password
    password=$(ui_passwordbox "Add User" "Enter password:") || return

    if [[ -z "$password" ]]; then
        ui_msgbox "Error" "Password cannot be empty"
        return 1
    fi

    # Confirm password
    local password_confirm
    password_confirm=$(ui_passwordbox "Add User" "Confirm password:") || return

    if [[ "$password" != "$password_confirm" ]]; then
        ui_msgbox "Error" "Passwords do not match"
        return 1
    fi

    # Select groups
    local groups_list=()
    while IFS= read -r group; do
        groups_list+=("$group" "" "off")
    done < <(get_all_groups)

    local selected_groups
    selected_groups=$(ui_checklist "Add User" "Select additional groups for $username:" "${groups_list[@]}") || true

    # Create user
    local create_cmd="useradd -m"
    if [[ -n "$fullname" ]]; then
        create_cmd+=" -c \"$fullname\""
    fi
    create_cmd+=" $username"

    if eval "$create_cmd" 2>&1; then
        # Set password
        echo "$username:$password" | chpasswd

        # Add to groups
        if [[ -n "$selected_groups" ]]; then
            # Remove quotes and convert to comma-separated
            local groups_csv
            groups_csv=$(echo "$selected_groups" | tr -d '"' | tr ' ' ',')
            usermod -aG "$groups_csv" "$username"
        fi

        log_info "Created user: $username"
        ui_msgbox "Success" "User '$username' created successfully"
    else
        log_error "Failed to create user: $username"
        ui_msgbox "Error" "Failed to create user '$username'"
    fi
}

# Modify user groups
modify_user_groups() {
    if ! require_root; then
        return 1
    fi

    # Get list of users
    local users_list=()
    while IFS= read -r user; do
        users_list+=("$user" "$(id -nG "$user" | tr ' ' ',')")
    done < <(get_regular_users)

    if [[ ${#users_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No regular users found"
        return
    fi

    # Select user
    local username
    username=$(ui_menu "Modify Groups" "Select user to modify:" "${users_list[@]}") || return

    # Get current groups
    local current_groups
    current_groups=$(id -nG "$username")

    # Build group checklist
    local groups_list=()
    while IFS= read -r group; do
        local status="off"
        if echo "$current_groups" | grep -qw "$group"; then
            status="on"
        fi
        groups_list+=("$group" "" "$status")
    done < <(get_all_groups)

    # Select new groups
    local selected_groups
    selected_groups=$(ui_checklist "Modify Groups" "Select groups for $username:" "${groups_list[@]}") || return

    # Convert to comma-separated list
    local groups_csv
    groups_csv=$(echo "$selected_groups" | tr -d '"' | tr ' ' ',')

    # Get user's primary group
    local primary_group
    primary_group=$(id -gn "$username")

    # Set groups (replace all supplementary groups)
    if [[ -n "$groups_csv" ]]; then
        usermod -G "$groups_csv" "$username"
    else
        # Remove all supplementary groups
        usermod -G "" "$username"
    fi

    log_info "Modified groups for user: $username"
    ui_msgbox "Success" "Groups updated for '$username'"
}

# Delete a user
delete_user() {
    if ! require_root; then
        return 1
    fi

    # Get list of users
    local users_list=()
    while IFS= read -r user; do
        local user_info
        user_info=$(getent passwd "$user" | cut -d: -f5 | cut -d, -f1)
        users_list+=("$user" "${user_info:-No description}")
    done < <(get_regular_users)

    if [[ ${#users_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No regular users found"
        return
    fi

    # Select user
    local username
    username=$(ui_menu "Delete User" "Select user to delete:" "${users_list[@]}") || return

    # Confirm deletion
    if ! ui_yesno "Confirm Delete" "Are you sure you want to delete user '$username'?\n\nThis action cannot be undone."; then
        return
    fi

    # Ask about home directory
    local delete_home=""
    if ui_yesno "Delete Home" "Also delete home directory (/home/$username)?"; then
        delete_home="-r"
    fi

    # Delete user
    if userdel $delete_home "$username" 2>&1; then
        log_info "Deleted user: $username"
        ui_msgbox "Success" "User '$username' deleted successfully"
    else
        log_error "Failed to delete user: $username"
        ui_msgbox "Error" "Failed to delete user '$username'"
    fi
}

# Show user information
user_info() {
    # Get list of users
    local users_list=()
    while IFS= read -r user; do
        users_list+=("$user" "UID: $(id -u "$user")")
    done < <(get_regular_users)

    # Add option to view all users
    users_list+=("ALL" "Show all system users")

    if [[ ${#users_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No regular users found"
        return
    fi

    # Select user
    local username
    username=$(ui_menu "User Info" "Select user to view:" "${users_list[@]}") || return

    local info=""

    if [[ "$username" == "ALL" ]]; then
        info="=== All System Users ===\n\n"
        info+="$(printf '%-15s %-6s %-6s %s\n' 'USERNAME' 'UID' 'GID' 'HOME')\n"
        info+="$(printf '%s\n' '-------------------------------------------')\n"
        while IFS=: read -r uname _ uid gid _ home _; do
            info+="$(printf '%-15s %-6s %-6s %s\n' "$uname" "$uid" "$gid" "$home")\n"
        done < /etc/passwd
    else
        local passwd_info
        passwd_info=$(getent passwd "$username")

        local uid gid fullname home shell
        uid=$(echo "$passwd_info" | cut -d: -f3)
        gid=$(echo "$passwd_info" | cut -d: -f4)
        fullname=$(echo "$passwd_info" | cut -d: -f5 | cut -d, -f1)
        home=$(echo "$passwd_info" | cut -d: -f6)
        shell=$(echo "$passwd_info" | cut -d: -f7)

        local groups
        groups=$(id -nG "$username" | tr ' ' '\n' | sort | tr '\n' ', ' | sed 's/,$//')

        local last_login
        last_login=$(lastlog -u "$username" 2>/dev/null | tail -1 | awk '{if ($2 == "**Never") print "Never"; else print $4" "$5" "$6" "$7}')

        local passwd_status
        passwd_status=$(passwd -S "$username" 2>/dev/null | awk '{print $2}')
        local status_text="Unknown"
        case "$passwd_status" in
            P) status_text="Password set" ;;
            L) status_text="Locked" ;;
            NP) status_text="No password" ;;
        esac

        info="=== User Information: $username ===\n\n"
        info+="Full Name:    ${fullname:-Not set}\n"
        info+="UID:          $uid\n"
        info+="GID:          $gid\n"
        info+="Home:         $home\n"
        info+="Shell:        $shell\n"
        info+="Groups:       $groups\n"
        info+="Last Login:   $last_login\n"
        info+="Password:     $status_text\n"

        # Show home directory size if it exists
        if [[ -d "$home" ]]; then
            local home_size
            home_size=$(du -sh "$home" 2>/dev/null | cut -f1)
            info+="Home Size:    $home_size\n"
        fi
    fi

    # Show info in a message box (use echo -e to interpret \n)
    echo -e "$info" > /tmp/user_info.txt
    ui_textbox "User Information" /tmp/user_info.txt
    rm -f /tmp/user_info.txt
}

# Change user password
change_password() {
    if ! require_root; then
        return 1
    fi

    # Get list of users
    local users_list=()
    users_list+=("root" "Root user")
    while IFS= read -r user; do
        users_list+=("$user" "UID: $(id -u "$user")")
    done < <(get_regular_users)

    # Select user
    local username
    username=$(ui_menu "Change Password" "Select user:" "${users_list[@]}") || return

    # Get new password
    local password
    password=$(ui_passwordbox "Change Password" "Enter new password for $username:") || return

    if [[ -z "$password" ]]; then
        ui_msgbox "Error" "Password cannot be empty"
        return 1
    fi

    # Confirm password
    local password_confirm
    password_confirm=$(ui_passwordbox "Change Password" "Confirm password:") || return

    if [[ "$password" != "$password_confirm" ]]; then
        ui_msgbox "Error" "Passwords do not match"
        return 1
    fi

    # Change password
    if echo "$username:$password" | chpasswd; then
        log_info "Changed password for user: $username"
        ui_msgbox "Success" "Password changed for '$username'"
    else
        log_error "Failed to change password for: $username"
        ui_msgbox "Error" "Failed to change password"
    fi
}

# Lock user account
lock_user() {
    if ! require_root; then
        return 1
    fi

    # Get list of unlocked users
    local users_list=()
    while IFS= read -r user; do
        local status
        status=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')
        if [[ "$status" != "L" ]]; then
            users_list+=("$user" "Status: Active")
        fi
    done < <(get_regular_users)

    if [[ ${#users_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No unlocked users found"
        return
    fi

    # Select user
    local username
    username=$(ui_menu "Lock User" "Select user to lock:" "${users_list[@]}") || return

    if ui_yesno "Confirm" "Lock user account '$username'?\n\nThe user will not be able to log in."; then
        if usermod -L "$username"; then
            log_info "Locked user account: $username"
            ui_msgbox "Success" "User '$username' has been locked"
        else
            ui_msgbox "Error" "Failed to lock user"
        fi
    fi
}

# Unlock user account
unlock_user() {
    if ! require_root; then
        return 1
    fi

    # Get list of locked users
    local users_list=()
    while IFS= read -r user; do
        local status
        status=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')
        if [[ "$status" == "L" ]]; then
            users_list+=("$user" "Status: Locked")
        fi
    done < <(get_regular_users)

    if [[ ${#users_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No locked users found"
        return
    fi

    # Select user
    local username
    username=$(ui_menu "Unlock User" "Select user to unlock:" "${users_list[@]}") || return

    if usermod -U "$username"; then
        log_info "Unlocked user account: $username"
        ui_msgbox "Success" "User '$username' has been unlocked"
    else
        ui_msgbox "Error" "Failed to unlock user"
    fi
}

# Set user shell
set_shell() {
    if ! require_root; then
        return 1
    fi

    # Get list of users
    local users_list=()
    while IFS= read -r user; do
        local shell
        shell=$(getent passwd "$user" | cut -d: -f7)
        users_list+=("$user" "Shell: $shell")
    done < <(get_regular_users)

    if [[ ${#users_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No regular users found"
        return
    fi

    # Select user
    local username
    username=$(ui_menu "Set Shell" "Select user:" "${users_list[@]}") || return

    # Get available shells
    local shells_list=()
    while IFS= read -r shell; do
        [[ -x "$shell" ]] && shells_list+=("$shell" "$(basename "$shell")")
    done < /etc/shells

    # Add nologin option
    shells_list+=("/usr/sbin/nologin" "Disable login")

    # Select shell
    local new_shell
    new_shell=$(ui_menu "Set Shell" "Select shell for $username:" "${shells_list[@]}") || return

    if usermod -s "$new_shell" "$username"; then
        log_info "Changed shell for $username to $new_shell"
        ui_msgbox "Success" "Shell changed to: $new_shell"
    else
        ui_msgbox "Error" "Failed to change shell"
    fi
}

# Force password change on next login
force_password_change() {
    if ! require_root; then
        return 1
    fi

    # Get list of users
    local users_list=()
    while IFS= read -r user; do
        users_list+=("$user" "UID: $(id -u "$user")")
    done < <(get_regular_users)

    if [[ ${#users_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No regular users found"
        return
    fi

    # Select user
    local username
    username=$(ui_menu "Force Password Change" "Select user:" "${users_list[@]}") || return

    if ui_yesno "Confirm" "Force '$username' to change password on next login?"; then
        if chage -d 0 "$username"; then
            log_info "Forced password change for: $username"
            ui_msgbox "Success" "User '$username' must change password on next login"
        else
            ui_msgbox "Error" "Failed to set password expiry"
        fi
    fi
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "User" "Select operation:" \
            "add" "Add new user" \
            "delete" "Delete user" \
            "expire" "Force password change" \
            "info" "View user information" \
            "lock" "Lock user account" \
            "modify" "Modify user groups" \
            "password" "Change password" \
            "shell" "Set user shell" \
            "unlock" "Unlock user account") || break

        case "$choice" in
            add)      add_user ;;
            delete)   delete_user ;;
            expire)   force_password_change ;;
            info)     user_info ;;
            lock)     lock_user ;;
            modify)   modify_user_groups ;;
            password) change_password ;;
            shell)    set_shell ;;
            unlock)   unlock_user ;;
        esac
    done
}
