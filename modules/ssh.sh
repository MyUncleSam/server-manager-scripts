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

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "SSH" "Select operation:" \
            "status" "Show SSH status" \
            "prompt" "Install colored prompt" \
            "prompt-remove" "Remove colored prompt" \
            "port" "Change SSH port" \
            "root" "Configure root login" \
            "password" "Configure password auth" \
            "harden" "Harden SSH (security)" \
            "advanced" "Advanced settings" \
            "keys" "Manage SSH keys" \
            "restart" "Restart SSH service") || break

        case "$choice" in
            status)        show_status ;;
            prompt)        install_custom_prompt ;;
            prompt-remove) remove_custom_prompt ;;
            port)          change_ssh_port ;;
            root)          configure_root_login ;;
            password)      configure_password_auth ;;
            harden)        harden_ssh ;;
            advanced)      configure_advanced ;;
            keys)          manage_keys ;;
            restart)       restart_ssh ;;
        esac
    done
}
