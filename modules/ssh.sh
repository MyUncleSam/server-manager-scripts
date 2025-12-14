#!/bin/bash
#
# SSH Manager Module
# Configure SSH server settings and security
#

# Module metadata
module_info() {
    echo "SSH|Configure SSH server and security"
}

# Configuration files
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_D="/etc/ssh/sshd_config.d"

# Prefix for our config files
CONFIG_PREFIX="server-manager"

# Shell prompt config
BASH_PROMPT_FILE="/etc/profile.d/custom-prompt.sh"

# Check if SSH is installed
check_ssh_installed() {
    if ! command_exists sshd; then
        if ui_yesno "SSH Not Installed" "OpenSSH server is not installed.\n\nWould you like to install it now?"; then
            if ! require_root; then
                return 1
            fi
            ui_infobox "Installing" "Installing OpenSSH server..."
            if install_packages openssh-server; then
                log_info "OpenSSH server installed"
                ui_msgbox "Success" "OpenSSH server installed successfully"
            else
                ui_msgbox "Error" "Failed to install OpenSSH server"
                return 1
            fi
        else
            return 1
        fi
    fi
    return 0
}

# Show SSH status
show_status() {
    if ! check_ssh_installed; then
        return 1
    fi

    local info=""
    info+="=== SSH Server Status ===\n\n"

    # Service status
    if service_is_running sshd || service_is_running ssh; then
        info+="Service:      Running\n"
    else
        info+="Service:      Stopped\n"
    fi

    # Get current settings
    local port
    port=$(grep "^Port " "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
    info+="Port:         ${port:-22}\n"

    local root_login
    root_login=$(grep "^PermitRootLogin " "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
    info+="Root Login:   ${root_login:-prohibit-password}\n"

    local password_auth
    password_auth=$(grep "^PasswordAuthentication " "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
    info+="Password Auth: ${password_auth:-yes}\n"

    local pubkey_auth
    pubkey_auth=$(grep "^PubkeyAuthentication " "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
    info+="Pubkey Auth:  ${pubkey_auth:-yes}\n"

    local x11_forward
    x11_forward=$(grep "^X11Forwarding " "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
    info+="X11 Forward:  ${x11_forward:-yes}\n"

    echo -e "$info" > /tmp/ssh_status.txt
    ui_textbox "SSH Status" /tmp/ssh_status.txt
    rm -f /tmp/ssh_status.txt
}

# Change SSH port
change_ssh_port() {
    if ! require_root; then
        return 1
    fi

    if ! check_ssh_installed; then
        return 1
    fi

    # Check current port from config.d or main config
    local current_port="22"
    local port_config="$SSHD_CONFIG_D/${CONFIG_PREFIX}-port.conf"
    if [[ -f "$port_config" ]]; then
        current_port=$(grep "^Port " "$port_config" 2>/dev/null | awk '{print $2}')
    elif grep -q "^Port " "$SSHD_CONFIG" 2>/dev/null; then
        current_port=$(grep "^Port " "$SSHD_CONFIG" | awk '{print $2}')
    fi
    current_port=${current_port:-22}

    local new_port
    new_port=$(ui_inputbox "SSH Port" "Enter new SSH port (1-65535):" "$current_port") || return

    if ! validate_port "$new_port"; then
        ui_msgbox "Error" "Invalid port number"
        return 1
    fi

    if [[ "$new_port" -lt 1024 && "$new_port" -ne 22 ]]; then
        if ! ui_yesno "Warning" "Port $new_port is a privileged port.\n\nAre you sure you want to use it?"; then
            return
        fi
    fi

    # Ensure config.d directory exists
    mkdir -p "$SSHD_CONFIG_D"

    # Create port config file
    echo "Port $new_port" > "$port_config"

    # Restart SSH
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null

    log_info "SSH port changed to $new_port"
    ui_msgbox "Success" "SSH port changed to $new_port\n\nIMPORTANT: Update your firewall rules!\n\nNew connection: ssh -p $new_port user@host"
}

# Configure root login
configure_root_login() {
    if ! require_root; then
        return 1
    fi

    if ! check_ssh_installed; then
        return 1
    fi

    local choice
    choice=$(ui_radiolist "Root Login" "Select root login setting:" \
        "prohibit-password" "Keys only (recommended)" "on" \
        "yes" "Allow with password" "off" \
        "no" "Disable completely" "off" \
        "forced-commands-only" "Forced commands only" "off") || return

    # Ensure config.d directory exists
    mkdir -p "$SSHD_CONFIG_D"

    # Create config file
    echo "PermitRootLogin $choice" > "$SSHD_CONFIG_D/${CONFIG_PREFIX}-permitrootlogin.conf"

    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null

    log_info "Root login set to: $choice"
    ui_msgbox "Success" "Root login set to: $choice"
}

# Configure password authentication
configure_password_auth() {
    if ! require_root; then
        return 1
    fi

    if ! check_ssh_installed; then
        return 1
    fi

    local choice
    choice=$(ui_radiolist "Password Auth" "Enable password authentication?" \
        "yes" "Enable" "on" \
        "no" "Disable (keys only)" "off") || return

    # Ensure config.d directory exists
    mkdir -p "$SSHD_CONFIG_D"

    # Create config file
    echo "PasswordAuthentication $choice" > "$SSHD_CONFIG_D/${CONFIG_PREFIX}-passwordauthentication.conf"

    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null

    log_info "Password authentication set to: $choice"
    ui_msgbox "Success" "Password authentication: $choice"
}

# Harden SSH configuration
harden_ssh() {
    if ! require_root; then
        return 1
    fi

    if ! check_ssh_installed; then
        return 1
    fi

    local info=""
    info+="This will apply the following security settings:\n\n"
    info+="• Disable root password login\n"
    info+="• Disable password authentication (keys only)\n"
    info+="• Disable empty passwords\n"
    info+="• Disable X11 forwarding\n"
    info+="• Set max auth tries to 3\n"
    info+="• Set login grace time to 60s\n"
    info+="• Disable TCP forwarding\n"
    info+="• Enable strict modes\n"
    info+="• Set client alive interval\n"

    if ! ui_yesno "Harden SSH" "$info"; then
        return
    fi

    # Ensure config.d directory exists
    mkdir -p "$SSHD_CONFIG_D"

    # Apply hardening settings - each in its own file
    declare -A settings=(
        ["PermitRootLogin"]="prohibit-password"
        ["PasswordAuthentication"]="no"
        ["PermitEmptyPasswords"]="no"
        ["X11Forwarding"]="no"
        ["MaxAuthTries"]="3"
        ["LoginGraceTime"]="60"
        ["AllowTcpForwarding"]="no"
        ["StrictModes"]="yes"
        ["ClientAliveInterval"]="60"
        ["ClientAliveCountMax"]="2"
    )

    for key in "${!settings[@]}"; do
        local value="${settings[$key]}"
        local config_file="$SSHD_CONFIG_D/${CONFIG_PREFIX}-${key,,}.conf"
        echo "$key $value" > "$config_file"
    done

    # Test configuration
    if sshd -t 2>&1; then
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
        log_info "SSH hardening applied"
        ui_msgbox "Success" "SSH has been hardened.\n\nMake sure you have key-based authentication set up before disconnecting!"
    else
        ui_msgbox "Error" "SSH configuration test failed.\n\nRemoving hardening configs..."
        rm -f "$SSHD_CONFIG_D/${CONFIG_PREFIX}-"*.conf
    fi
}

# Configure additional settings
configure_advanced() {
    if ! require_root; then
        return 1
    fi

    if ! check_ssh_installed; then
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Advanced Settings" "Select setting to configure:" \
            "x11" "X11 Forwarding" \
            "tcp" "TCP Forwarding" \
            "compression" "Compression" \
            "banner" "Login Banner" \
            "maxauth" "Max Auth Tries" \
            "timeout" "Connection Timeout") || break

        case "$choice" in
            x11)
                local x11
                x11=$(ui_radiolist "X11 Forwarding" "Enable X11 forwarding?" \
                    "yes" "Enable" "off" \
                    "no" "Disable" "on") || continue
                update_ssh_setting "X11Forwarding" "$x11"
                ;;
            tcp)
                local tcp
                tcp=$(ui_radiolist "TCP Forwarding" "Enable TCP forwarding?" \
                    "yes" "Enable" "off" \
                    "no" "Disable" "on") || continue
                update_ssh_setting "AllowTcpForwarding" "$tcp"
                ;;
            compression)
                local comp
                comp=$(ui_radiolist "Compression" "Enable compression?" \
                    "yes" "Enable" "on" \
                    "no" "Disable" "off") || continue
                update_ssh_setting "Compression" "$comp"
                ;;
            banner)
                local banner_file
                banner_file=$(ui_inputbox "Banner File" "Enter banner file path (empty to disable):" "/etc/ssh/banner") || continue
                if [[ -n "$banner_file" ]]; then
                    if [[ ! -f "$banner_file" ]]; then
                        echo "Welcome to $(hostname)" > "$banner_file"
                    fi
                    update_ssh_setting "Banner" "$banner_file"
                else
                    update_ssh_setting "Banner" "none"
                fi
                ;;
            maxauth)
                local max
                max=$(ui_inputbox "Max Auth Tries" "Enter maximum authentication attempts:" "3") || continue
                update_ssh_setting "MaxAuthTries" "$max"
                ;;
            timeout)
                local timeout
                timeout=$(ui_inputbox "Client Alive Interval" "Enter timeout in seconds (0 to disable):" "60") || continue
                update_ssh_setting "ClientAliveInterval" "$timeout"
                ;;
        esac
    done
}

# Helper to update SSH setting
update_ssh_setting() {
    local key="$1"
    local value="$2"

    # Ensure config.d directory exists
    mkdir -p "$SSHD_CONFIG_D"

    # Create individual config file for this setting
    local config_file="$SSHD_CONFIG_D/${CONFIG_PREFIX}-${key,,}.conf"

    echo "$key $value" > "$config_file"

    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null

    log_info "SSH setting updated: $key = $value"
    ui_msgbox "Success" "Setting updated:\n$key = $value\n\nConfig: $config_file"
}

# Manage SSH keys
manage_keys() {
    while true; do
        local choice
        choice=$(ui_menu "SSH Keys" "Select operation:" \
            "list" "List authorized keys" \
            "add" "Add authorized key" \
            "generate" "Generate new key pair" \
            "remove" "Remove authorized key") || break

        case "$choice" in
            list)   list_authorized_keys ;;
            add)    add_authorized_key ;;
            generate) generate_key_pair ;;
            remove) remove_authorized_key ;;
        esac
    done
}

# List authorized keys
list_authorized_keys() {
    local users
    users=$(get_regular_users)
    users="root $users"

    local user
    user=$(ui_menu "Select User" "View authorized keys for:" \
        $(for u in $users; do echo "$u" "$u"; done)) || return

    local auth_file
    if [[ "$user" == "root" ]]; then
        auth_file="/root/.ssh/authorized_keys"
    else
        auth_file="/home/$user/.ssh/authorized_keys"
    fi

    if [[ -f "$auth_file" ]]; then
        ui_textbox "Authorized Keys - $user" "$auth_file"
    else
        ui_msgbox "Info" "No authorized keys found for $user"
    fi
}

# Add authorized key
add_authorized_key() {
    if ! require_root; then
        return 1
    fi

    local users
    users=$(get_regular_users)
    users="root $users"

    local user
    user=$(ui_menu "Select User" "Add key for user:" \
        $(for u in $users; do echo "$u" "$u"; done)) || return

    local key
    key=$(ui_inputbox "SSH Public Key" "Paste the public key:") || return

    if [[ -z "$key" ]]; then
        ui_msgbox "Error" "Key cannot be empty"
        return 1
    fi

    # Validate key format
    if [[ ! "$key" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
        ui_msgbox "Error" "Invalid key format.\nKey should start with ssh-rsa, ssh-ed25519, or ssh-ecdsa"
        return 1
    fi

    local ssh_dir auth_file
    if [[ "$user" == "root" ]]; then
        ssh_dir="/root/.ssh"
    else
        ssh_dir="/home/$user/.ssh"
    fi
    auth_file="$ssh_dir/authorized_keys"

    # Create .ssh directory if needed
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown "$user:$user" "$ssh_dir" 2>/dev/null || chown "$user" "$ssh_dir"

    # Add key
    echo "$key" >> "$auth_file"
    chmod 600 "$auth_file"
    chown "$user:$user" "$auth_file" 2>/dev/null || chown "$user" "$auth_file"

    log_info "Added SSH key for user: $user"
    ui_msgbox "Success" "SSH key added for $user"
}

# Generate key pair
generate_key_pair() {
    local key_type
    key_type=$(ui_radiolist "Key Type" "Select key type:" \
        "ed25519" "ED25519 (recommended)" "on" \
        "rsa" "RSA 4096-bit" "off" \
        "ecdsa" "ECDSA" "off") || return

    local key_file
    key_file=$(ui_inputbox "Key File" "Enter key file path:" "$HOME/.ssh/id_$key_type") || return

    local comment
    comment=$(ui_inputbox "Comment" "Enter key comment:" "$(whoami)@$(hostname)") || return

    # Generate key
    local output
    case "$key_type" in
        ed25519)
            output=$(ssh-keygen -t ed25519 -f "$key_file" -C "$comment" -N "" 2>&1)
            ;;
        rsa)
            output=$(ssh-keygen -t rsa -b 4096 -f "$key_file" -C "$comment" -N "" 2>&1)
            ;;
        ecdsa)
            output=$(ssh-keygen -t ecdsa -b 521 -f "$key_file" -C "$comment" -N "" 2>&1)
            ;;
    esac

    if [[ -f "$key_file" ]]; then
        log_info "Generated SSH key pair: $key_file"

        local pub_key
        pub_key=$(cat "${key_file}.pub")

        echo -e "Key pair generated!\n\nPrivate key: $key_file\nPublic key: ${key_file}.pub\n\nPublic key content:\n$pub_key" > /tmp/keygen_result.txt
        ui_textbox "Key Generated" /tmp/keygen_result.txt
        rm -f /tmp/keygen_result.txt
    else
        ui_msgbox "Error" "Failed to generate key:\n$output"
    fi
}

# Remove authorized key
remove_authorized_key() {
    if ! require_root; then
        return 1
    fi

    local users
    users=$(get_regular_users)
    users="root $users"

    local user
    user=$(ui_menu "Select User" "Remove key from user:" \
        $(for u in $users; do echo "$u" "$u"; done)) || return

    local auth_file
    if [[ "$user" == "root" ]]; then
        auth_file="/root/.ssh/authorized_keys"
    else
        auth_file="/home/$user/.ssh/authorized_keys"
    fi

    if [[ ! -f "$auth_file" ]]; then
        ui_msgbox "Info" "No authorized keys found for $user"
        return
    fi

    # Show keys with numbers
    local keys
    keys=$(nl -ba "$auth_file")

    echo -e "Authorized keys for $user:\n\n$keys" > /tmp/auth_keys.txt
    ui_textbox "Authorized Keys" /tmp/auth_keys.txt
    rm -f /tmp/auth_keys.txt

    local line_num
    line_num=$(ui_inputbox "Remove Key" "Enter line number to remove:") || return

    if [[ ! "$line_num" =~ ^[0-9]+$ ]]; then
        ui_msgbox "Error" "Invalid line number"
        return 1
    fi

    if ui_yesno "Confirm" "Remove key on line $line_num?"; then
        sed -i "${line_num}d" "$auth_file"
        log_info "Removed SSH key for user: $user (line $line_num)"
        ui_msgbox "Success" "Key removed"
    fi
}

# Restart SSH service
restart_ssh() {
    if ! require_root; then
        return 1
    fi

    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
        log_info "SSH service restarted"
        ui_msgbox "Success" "SSH service restarted"
    else
        ui_msgbox "Error" "Failed to restart SSH service"
    fi
}

# Install custom shell prompt with colors
install_custom_prompt() {
    if ! require_root; then
        return 1
    fi

    cat > "$BASH_PROMPT_FILE" << 'PROMPT_EOF'
# Custom shell prompt with colors
# Format: username@pretty-hostname /current/folder $
# Colors: username (red/green), @ (yellow), hostname (light blue), path (yellow)
# Generated by SSH Manager

if [ "$BASH" ]; then
    # Get pretty hostname, fallback to regular hostname
    __get_pretty_host() {
        local pretty
        pretty=$(hostnamectl --pretty 2>/dev/null)
        if [ -n "$pretty" ]; then
            echo "$pretty"
        else
            hostname
        fi
    }

    if [ "$(id -u)" -eq 0 ]; then
        # Root user - Red username
        PS1='\[\033[01;31m\]\u\[\033[01;33m\]@\[\033[01;36m\]$(__get_pretty_host)\[\033[00m\] \[\033[01;33m\]\w\[\033[00m\] \$ '
    else
        # Regular user - Green username
        PS1='\[\033[01;32m\]\u\[\033[01;33m\]@\[\033[01;36m\]$(__get_pretty_host)\[\033[00m\] \[\033[01;33m\]\w\[\033[00m\] \$ '
    fi
fi
PROMPT_EOF

    chmod +x "$BASH_PROMPT_FILE"

    log_info "Custom shell prompt installed"

    # Ask to apply to existing users
    if ui_yesno "Apply to Users" "Apply prompt to existing users?\n\nThis will update .bashrc for all users to ensure the prompt is used even if they have custom settings."; then
        apply_prompt_to_users
    fi

    ui_msgbox "Success" "Custom shell prompt installed.\n\nFormat: username@pretty-hostname /path $\n\n- Username: Red (root) / Green (users)\n- @: Yellow\n- Hostname: Light Blue\n- Path: Yellow\n\nLog out and back in to see changes."
}

# Apply prompt to all existing users
apply_prompt_to_users() {
    local prompt_source="
# Custom prompt - Generated by SSH Manager
if [ -f $BASH_PROMPT_FILE ]; then
    . $BASH_PROMPT_FILE
fi"

    local marker="# Custom prompt - Generated by SSH Manager"
    local updated=0

    # Apply to root
    if [[ -f /root/.bashrc ]]; then
        # Remove old entry if exists
        sed -i "/$marker/,/fi$/d" /root/.bashrc 2>/dev/null
        # Add new entry
        echo "$prompt_source" >> /root/.bashrc
        ((updated++))
    fi

    # Apply to regular users
    local users
    users=$(get_regular_users)
    for user in $users; do
        local bashrc="/home/$user/.bashrc"
        if [[ -f "$bashrc" ]]; then
            # Remove old entry if exists
            sed -i "/$marker/,/fi$/d" "$bashrc" 2>/dev/null
            # Add new entry
            echo "$prompt_source" >> "$bashrc"
            chown "$user:$user" "$bashrc"
            ((updated++))
        fi
    done

    log_info "Applied custom prompt to $updated user(s)"
}

# Remove custom prompt
remove_custom_prompt() {
    if ! require_root; then
        return 1
    fi

    if [[ -f "$BASH_PROMPT_FILE" ]]; then
        rm -f "$BASH_PROMPT_FILE"

        # Clean up .bashrc entries
        local marker="# Custom prompt - Generated by SSH Manager"

        # Clean root
        if [[ -f /root/.bashrc ]]; then
            sed -i "/$marker/,/fi$/d" /root/.bashrc 2>/dev/null
        fi

        # Clean regular users
        local users
        users=$(get_regular_users)
        for user in $users; do
            local bashrc="/home/$user/.bashrc"
            if [[ -f "$bashrc" ]]; then
                sed -i "/$marker/,/fi$/d" "$bashrc" 2>/dev/null
            fi
        done

        log_info "Custom shell prompt removed"
        ui_msgbox "Success" "Custom shell prompt removed.\n\nLog out and back in for default prompt."
    else
        ui_msgbox "Info" "Custom prompt is not installed"
    fi
}

# Configure allowed users
configure_allowed_users() {
    if ! require_root; then
        return 1
    fi

    if ! check_ssh_installed; then
        return 1
    fi

    local choice
    choice=$(ui_menu "User Access" "Select configuration:" \
        "allow" "Set AllowUsers" \
        "deny" "Set DenyUsers" \
        "clear" "Clear user restrictions") || return

    case "$choice" in
        allow)
            local users
            users=$(ui_inputbox "AllowUsers" "Enter usernames (space-separated):\n\nOnly these users can login via SSH." "root") || return
            mkdir -p "$SSHD_CONFIG_D"
            echo "AllowUsers $users" > "$SSHD_CONFIG_D/${CONFIG_PREFIX}-allowusers.conf"
            rm -f "$SSHD_CONFIG_D/${CONFIG_PREFIX}-denyusers.conf"
            systemctl restart sshd 2>/dev/null || systemctl restart ssh
            log_info "Set SSH AllowUsers: $users"
            ui_msgbox "Success" "AllowUsers set to: $users"
            ;;
        deny)
            local users
            users=$(ui_inputbox "DenyUsers" "Enter usernames (space-separated):\n\nThese users cannot login via SSH.") || return
            mkdir -p "$SSHD_CONFIG_D"
            echo "DenyUsers $users" > "$SSHD_CONFIG_D/${CONFIG_PREFIX}-denyusers.conf"
            rm -f "$SSHD_CONFIG_D/${CONFIG_PREFIX}-allowusers.conf"
            systemctl restart sshd 2>/dev/null || systemctl restart ssh
            log_info "Set SSH DenyUsers: $users"
            ui_msgbox "Success" "DenyUsers set to: $users"
            ;;
        clear)
            rm -f "$SSHD_CONFIG_D/${CONFIG_PREFIX}-allowusers.conf"
            rm -f "$SSHD_CONFIG_D/${CONFIG_PREFIX}-denyusers.conf"
            systemctl restart sshd 2>/dev/null || systemctl restart ssh
            log_info "Cleared SSH user restrictions"
            ui_msgbox "Success" "User restrictions cleared"
            ;;
    esac
}

# Show active SSH sessions
show_active_sessions() {
    local info=""
    info+="=== Active SSH Sessions ===\n\n"
    info+="$(who 2>&1)\n"
    info+="\n=== SSH Connections ===\n\n"
    info+="$(ss -tnp | grep ssh 2>&1)\n"

    echo -e "$info" > /tmp/ssh_sessions.txt
    ui_textbox "Active Sessions" /tmp/ssh_sessions.txt
    rm -f /tmp/ssh_sessions.txt
}

# Kick SSH session
kick_session() {
    if ! require_root; then
        return 1
    fi

    # Get list of sessions
    local sessions_list=()
    while IFS= read -r line; do
        local user tty
        user=$(echo "$line" | awk '{print $1}')
        tty=$(echo "$line" | awk '{print $2}')
        [[ -n "$user" && -n "$tty" ]] && sessions_list+=("$tty" "$user")
    done < <(who | grep pts)

    if [[ ${#sessions_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No active SSH sessions found"
        return
    fi

    local tty
    tty=$(ui_menu "Kick Session" "Select session to terminate:" "${sessions_list[@]}") || return

    if ui_yesno "Confirm" "Terminate session on $tty?"; then
        pkill -9 -t "$tty"
        log_info "Kicked SSH session: $tty"
        ui_msgbox "Success" "Session terminated"
    fi
}

# View auth log
view_auth_log() {
    local log_file="/var/log/auth.log"

    if [[ ! -f "$log_file" ]]; then
        log_file="/var/log/secure"
    fi

    if [[ ! -f "$log_file" ]]; then
        ui_msgbox "Error" "Auth log not found"
        return
    fi

    local choice
    choice=$(ui_menu "Auth Log" "Select view:" \
        "recent" "Recent entries (last 100)" \
        "failed" "Failed login attempts" \
        "success" "Successful logins" \
        "all" "All SSH entries") || return

    local content=""
    case "$choice" in
        recent)
            content=$(tail -100 "$log_file")
            ;;
        failed)
            content=$(grep -i "failed\|invalid\|error" "$log_file" | tail -100)
            ;;
        success)
            content=$(grep -i "accepted\|opened" "$log_file" | tail -100)
            ;;
        all)
            content=$(grep -i "sshd" "$log_file" | tail -100)
            ;;
    esac

    echo "$content" > /tmp/auth_log.txt
    ui_textbox "Auth Log" /tmp/auth_log.txt
    rm -f /tmp/auth_log.txt
}

# Add new user with SSH key
add_user_with_key() {
    if ! require_root; then
        return 1
    fi

    # Get username
    local username
    username=$(ui_inputbox "New User" "Enter username:") || return

    if [[ -z "$username" ]]; then
        ui_msgbox "Error" "Username cannot be empty"
        return 1
    fi

    # Validate username
    if ! validate_username "$username"; then
        ui_msgbox "Error" "Invalid username format"
        return 1
    fi

    # Check if user already exists
    if user_exists "$username"; then
        ui_msgbox "Error" "User $username already exists"
        return 1
    fi

    # Select shell
    local shell
    shell=$(ui_radiolist "Select Shell" "Choose default shell for $username:" \
        "/bin/bash" "Bash (recommended)" "on" \
        "/bin/sh" "Sh (minimal)" "off" \
        "/bin/zsh" "Zsh (if installed)" "off" \
        "/bin/fish" "Fish (if installed)" "off") || return

    # Verify shell exists
    if [[ ! -x "$shell" ]]; then
        if ! ui_yesno "Shell Not Found" "Shell $shell is not installed or not executable.\n\nUse /bin/bash instead?"; then
            return
        fi
        shell="/bin/bash"
    fi

    # Get public key
    local key
    key=$(ui_inputbox "SSH Public Key" "Paste the public key for $username:") || return

    if [[ -z "$key" ]]; then
        ui_msgbox "Error" "Key cannot be empty"
        return 1
    fi

    # Validate key format
    if [[ ! "$key" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
        ui_msgbox "Error" "Invalid key format.\nKey should start with ssh-rsa, ssh-ed25519, or ssh-ecdsa"
        return 1
    fi

    # Create user
    ui_infobox "Creating User" "Creating user $username with shell $shell..."
    if ! useradd -m -s "$shell" "$username" 2>/dev/null; then
        ui_msgbox "Error" "Failed to create user $username"
        return 1
    fi

    # Setup SSH directory and key
    local ssh_dir="/home/$username/.ssh"
    local auth_file="$ssh_dir/authorized_keys"

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    echo "$key" > "$auth_file"
    chmod 600 "$auth_file"
    chown -R "$username:$username" "$ssh_dir"

    log_info "Created user $username with SSH key (shell: $shell)"
    ui_msgbox "Success" "User $username created successfully.\n\nShell: $shell\nSSH key configured - user can login via SSH with their private key.\n\nNote: User has no password set. Use 'passwd $username' to set one if needed."
}

# Manage sudoers
manage_sudoers() {
    if ! require_root; then
        return 1
    fi

    while true; do
        local choice
        choice=$(ui_menu "Sudoers Management" "Select operation:" \
            "add" "Add user to sudoers" \
            "remove" "Remove user from sudoers" \
            "list" "List sudo users") || break

        case "$choice" in
            add) add_user_to_sudoers ;;
            remove) remove_user_from_sudoers ;;
            list) list_sudo_users ;;
        esac
    done
}

# Add user to sudoers
add_user_to_sudoers() {
    # Get list of users
    local users
    users=$(get_regular_users)

    if [[ -z "$users" ]]; then
        ui_msgbox "Error" "No users found"
        return 1
    fi

    # Select user
    local user
    user=$(ui_menu "Select User" "Add user to sudoers:" \
        $(for u in $users; do echo "$u" "$u"; done)) || return

    # Ask if passwordless
    local passwordless="no"
    if ui_yesno "Passwordless Sudo" "Allow $user to use sudo without password?\n\nWARNING: This allows the user to become root without entering a password.\n\nUser will be able to run 'sudo su -' to switch to root without password."; then
        passwordless="yes"
    fi

    # Create sudoers file
    local sudoers_file="/etc/sudoers.d/server-manager-$user"

    if [[ "$passwordless" == "yes" ]]; then
        echo "$user ALL=(ALL) NOPASSWD:ALL" > "$sudoers_file"
    else
        echo "$user ALL=(ALL:ALL) ALL" > "$sudoers_file"
    fi

    chmod 440 "$sudoers_file"

    # Validate sudoers file
    if visudo -c -f "$sudoers_file" >/dev/null 2>&1; then
        log_info "Added $user to sudoers (passwordless: $passwordless)"

        local msg="User $user added to sudoers.\n\n"
        if [[ "$passwordless" == "yes" ]]; then
            msg+="Passwordless sudo: YES\n\n"
            msg+="User can:\n"
            msg+="  • Run 'sudo su -' to become root\n"
            msg+="  • Run any sudo command without password"
        else
            msg+="Passwordless sudo: NO\n\n"
            msg+="User must enter their password to use sudo."
        fi

        ui_msgbox "Success" "$msg"
    else
        rm -f "$sudoers_file"
        ui_msgbox "Error" "Failed to create valid sudoers configuration"
        return 1
    fi
}

# Remove user from sudoers
remove_user_from_sudoers() {
    # Get list of users with sudoers files
    local sudoers_users=()
    for file in /etc/sudoers.d/server-manager-*; do
        if [[ -f "$file" ]]; then
            local username="${file##*/server-manager-}"
            sudoers_users+=("$username" "$username")
        fi
    done

    if [[ ${#sudoers_users[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No users found in sudoers (managed by this tool)"
        return
    fi

    # Select user
    local user
    user=$(ui_menu "Select User" "Remove user from sudoers:" "${sudoers_users[@]}") || return

    if ui_yesno "Confirm" "Remove sudo privileges for $user?"; then
        rm -f "/etc/sudoers.d/server-manager-$user"
        log_info "Removed $user from sudoers"
        ui_msgbox "Success" "Sudo privileges removed for $user"
    fi
}

# List sudo users
list_sudo_users() {
    local info=""
    info+="=== Sudo Users ===\n\n"
    info+="Users in 'sudo' group:\n"
    local sudo_group
    sudo_group=$(getent group sudo 2>/dev/null | cut -d: -f4)
    if [[ -n "$sudo_group" ]]; then
        echo "$sudo_group" | tr ',' '\n' | while read -r user; do
            [[ -n "$user" ]] && info+="  - $user\n"
        done
    else
        info+="  (none)\n"
    fi

    info+="\nUsers managed by this tool:\n"
    local found=0
    for file in /etc/sudoers.d/server-manager-*; do
        if [[ -f "$file" ]]; then
            local username="${file##*/server-manager-}"
            local config=$(cat "$file")
            if echo "$config" | grep -q "NOPASSWD"; then
                info+="  - $username (passwordless)\n"
            else
                info+="  - $username\n"
            fi
            found=1
        fi
    done

    if [[ $found -eq 0 ]]; then
        info+="  (none)\n"
    fi

    echo -e "$info" > /tmp/sudo_users.txt
    ui_textbox "Sudo Users" /tmp/sudo_users.txt
    rm -f /tmp/sudo_users.txt
}

# Manage SSH users submenu
manage_ssh_users() {
    while true; do
        local choice
        choice=$(ui_menu "SSH Users" "Select operation:" \
            "add" "Add user with SSH key") || break

        case "$choice" in
            add) add_user_with_key ;;
        esac
    done
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "SSH" "Select operation:" \
            "status" "Show SSH status" \
            "sessions" "Show active sessions" \
            "kick" "Kick session" \
            "authlog" "View auth log" \
            "users" "Manage SSH users" \
            "sudoers" "Manage sudoers" \
            "port" "Change SSH port" \
            "root" "Configure root login" \
            "password" "Configure password auth" \
            "allowlist" "Configure allowed users" \
            "keys" "Manage SSH keys" \
            "harden" "Harden SSH (security)" \
            "advanced" "Advanced settings" \
            "prompt" "Install colored prompt" \
            "prompt-remove" "Remove colored prompt" \
            "restart" "Restart SSH service") || break

        case "$choice" in
            status)        show_status ;;
            sessions)      show_active_sessions ;;
            kick)          kick_session ;;
            authlog)       view_auth_log ;;
            users)         manage_ssh_users ;;
            sudoers)       manage_sudoers ;;
            port)          change_ssh_port ;;
            root)          configure_root_login ;;
            password)      configure_password_auth ;;
            allowlist)     configure_allowed_users ;;
            keys)          manage_keys ;;
            harden)        harden_ssh ;;
            advanced)      configure_advanced ;;
            prompt)        install_custom_prompt ;;
            prompt-remove) remove_custom_prompt ;;
            restart)       restart_ssh ;;
        esac
    done
}
