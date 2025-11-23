#!/bin/bash
#
# Software Installer Module
# Install software not available via APT
#

# Module metadata
module_info() {
    echo "Software|Install software not available via APT"
}

# Check if a command exists
is_installed() {
    command -v "$1" &>/dev/null
}

# Show installation status
show_status() {
    local info=""
    info+="=== Software Installation Status ===\n\n"

    # Check each software
    if is_installed rclone; then
        info+="rclone:        Installed ($(rclone version | head -1 | awk '{print $2}'))\n"
    else
        info+="rclone:        Not installed\n"
    fi

    if is_installed lazydocker; then
        info+="lazydocker:    Installed\n"
    else
        info+="lazydocker:    Not installed\n"
    fi

    if is_installed lazygit; then
        info+="lazygit:       Installed\n"
    else
        info+="lazygit:       Not installed\n"
    fi

    if is_installed btop; then
        info+="btop:          Installed\n"
    else
        info+="btop:          Not installed\n"
    fi

    if is_installed bat; then
        info+="bat:           Installed\n"
    else
        info+="bat:           Not installed\n"
    fi

    if is_installed fd; then
        info+="fd:            Installed\n"
    else
        info+="fd:            Not installed\n"
    fi

    if is_installed rg; then
        info+="ripgrep:       Installed\n"
    else
        info+="ripgrep:       Not installed\n"
    fi

    if is_installed fzf; then
        info+="fzf:           Installed\n"
    else
        info+="fzf:           Not installed\n"
    fi

    if is_installed yq; then
        info+="yq:            Installed ($(yq --version 2>/dev/null | awk '{print $NF}'))\n"
    else
        info+="yq:            Not installed\n"
    fi

    if is_installed starship; then
        info+="starship:      Installed\n"
    else
        info+="starship:      Not installed\n"
    fi

    echo -e "$info" > /tmp/software_status.txt
    ui_textbox "Software Status" /tmp/software_status.txt
    rm -f /tmp/software_status.txt
}

# Install rclone
install_rclone() {
    if ! require_root; then
        return 1
    fi

    if is_installed rclone; then
        local current_ver
        current_ver=$(rclone version | head -1 | awk '{print $2}')
        if ! ui_yesno "Already Installed" "rclone $current_ver is already installed.\n\nReinstall/Update?"; then
            return 0
        fi
    fi

    if ! has_internet; then
        ui_msgbox "Error" "Internet connection required"
        return 1
    fi

    ui_infobox "Installing" "Installing rclone..."

    # Use official install script
    if curl -fsSL https://rclone.org/install.sh | bash 2>&1; then
        log_info "rclone installed"
        local ver
        ver=$(rclone version | head -1)
        ui_msgbox "Success" "rclone installed successfully\n\n$ver"
    else
        ui_msgbox "Error" "Failed to install rclone"
        return 1
    fi
}

# Uninstall rclone
uninstall_rclone() {
    if ! require_root; then
        return 1
    fi

    if ! is_installed rclone; then
        ui_msgbox "Info" "rclone is not installed"
        return 0
    fi

    if ui_yesno "Uninstall rclone" "Are you sure you want to uninstall rclone?"; then
        rm -f /usr/bin/rclone
        rm -f /usr/local/share/man/man1/rclone.1
        log_info "rclone uninstalled"
        ui_msgbox "Success" "rclone uninstalled"
    fi
}

# Install lazydocker
install_lazydocker() {
    if ! require_root; then
        return 1
    fi

    if is_installed lazydocker; then
        if ! ui_yesno "Already Installed" "lazydocker is already installed.\n\nReinstall/Update?"; then
            return 0
        fi
    fi

    if ! has_internet; then
        ui_msgbox "Error" "Internet connection required"
        return 1
    fi

    ui_infobox "Installing" "Installing lazydocker..."

    # Use official install script
    if curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash 2>&1; then
        # Move to system path
        if [[ -f "$HOME/.local/bin/lazydocker" ]]; then
            mv "$HOME/.local/bin/lazydocker" /usr/local/bin/
        fi
        log_info "lazydocker installed"
        ui_msgbox "Success" "lazydocker installed successfully"
    else
        ui_msgbox "Error" "Failed to install lazydocker"
        return 1
    fi
}

# Install lazygit
install_lazygit() {
    if ! require_root; then
        return 1
    fi

    if is_installed lazygit; then
        if ! ui_yesno "Already Installed" "lazygit is already installed.\n\nReinstall/Update?"; then
            return 0
        fi
    fi

    if ! has_internet; then
        ui_msgbox "Error" "Internet connection required"
        return 1
    fi

    ui_infobox "Installing" "Installing lazygit..."

    # Get latest version
    local latest_ver
    latest_ver=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r .tag_name | tr -d 'v')

    if [[ -z "$latest_ver" ]]; then
        ui_msgbox "Error" "Failed to get latest version"
        return 1
    fi

    local arch
    arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        arch="x86_64"
    elif [[ "$arch" == "aarch64" ]]; then
        arch="arm64"
    fi

    local url="https://github.com/jesseduffield/lazygit/releases/download/v${latest_ver}/lazygit_${latest_ver}_Linux_${arch}.tar.gz"

    cd /tmp
    if curl -fsSL "$url" -o lazygit.tar.gz; then
        tar xzf lazygit.tar.gz lazygit
        mv lazygit /usr/local/bin/
        rm -f lazygit.tar.gz
        log_info "lazygit $latest_ver installed"
        ui_msgbox "Success" "lazygit $latest_ver installed"
    else
        ui_msgbox "Error" "Failed to download lazygit"
        return 1
    fi
}

# Install btop
install_btop() {
    if ! require_root; then
        return 1
    fi

    if is_installed btop; then
        if ! ui_yesno "Already Installed" "btop is already installed.\n\nReinstall/Update?"; then
            return 0
        fi
    fi

    if ! has_internet; then
        ui_msgbox "Error" "Internet connection required"
        return 1
    fi

    ui_infobox "Installing" "Installing btop..."

    # Get latest version
    local latest_ver
    latest_ver=$(curl -fsSL https://api.github.com/repos/aristocratos/btop/releases/latest | jq -r .tag_name | tr -d 'v')

    if [[ -z "$latest_ver" ]]; then
        ui_msgbox "Error" "Failed to get latest version"
        return 1
    fi

    local arch
    arch=$(uname -m)

    local url="https://github.com/aristocratos/btop/releases/download/v${latest_ver}/btop-${arch}-linux-musl.tbz"

    cd /tmp
    if curl -fsSL "$url" -o btop.tbz; then
        tar xjf btop.tbz
        cd btop
        make install PREFIX=/usr/local
        cd /tmp
        rm -rf btop btop.tbz
        log_info "btop $latest_ver installed"
        ui_msgbox "Success" "btop $latest_ver installed"
    else
        ui_msgbox "Error" "Failed to download btop"
        return 1
    fi
}

# Install bat (better cat)
install_bat() {
    if ! require_root; then
        return 1
    fi

    if is_installed bat; then
        if ! ui_yesno "Already Installed" "bat is already installed.\n\nReinstall/Update?"; then
            return 0
        fi
    fi

    if ! has_internet; then
        ui_msgbox "Error" "Internet connection required"
        return 1
    fi

    ui_infobox "Installing" "Installing bat..."

    # Get latest version
    local latest_ver
    latest_ver=$(curl -fsSL https://api.github.com/repos/sharkdp/bat/releases/latest | jq -r .tag_name | tr -d 'v')

    if [[ -z "$latest_ver" ]]; then
        ui_msgbox "Error" "Failed to get latest version"
        return 1
    fi

    local arch
    arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        arch="x86_64-unknown-linux-musl"
    elif [[ "$arch" == "aarch64" ]]; then
        arch="aarch64-unknown-linux-gnu"
    fi

    local url="https://github.com/sharkdp/bat/releases/download/v${latest_ver}/bat-v${latest_ver}-${arch}.tar.gz"

    cd /tmp
    if curl -fsSL "$url" -o bat.tar.gz; then
        tar xzf bat.tar.gz
        cp "bat-v${latest_ver}-${arch}/bat" /usr/local/bin/
        rm -rf bat.tar.gz "bat-v${latest_ver}-${arch}"
        log_info "bat $latest_ver installed"
        ui_msgbox "Success" "bat $latest_ver installed"
    else
        ui_msgbox "Error" "Failed to download bat"
        return 1
    fi
}

# Install fd (better find)
install_fd() {
    if ! require_root; then
        return 1
    fi

    if is_installed fd; then
        if ! ui_yesno "Already Installed" "fd is already installed.\n\nReinstall/Update?"; then
            return 0
        fi
    fi

    if ! has_internet; then
        ui_msgbox "Error" "Internet connection required"
        return 1
    fi

    ui_infobox "Installing" "Installing fd..."

    # Get latest version
    local latest_ver
    latest_ver=$(curl -fsSL https://api.github.com/repos/sharkdp/fd/releases/latest | jq -r .tag_name | tr -d 'v')

    if [[ -z "$latest_ver" ]]; then
        ui_msgbox "Error" "Failed to get latest version"
        return 1
    fi

    local arch
    arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        arch="x86_64-unknown-linux-musl"
    elif [[ "$arch" == "aarch64" ]]; then
        arch="aarch64-unknown-linux-gnu"
    fi

    local url="https://github.com/sharkdp/fd/releases/download/v${latest_ver}/fd-v${latest_ver}-${arch}.tar.gz"

    cd /tmp
    if curl -fsSL "$url" -o fd.tar.gz; then
        tar xzf fd.tar.gz
        cp "fd-v${latest_ver}-${arch}/fd" /usr/local/bin/
        rm -rf fd.tar.gz "fd-v${latest_ver}-${arch}"
        log_info "fd $latest_ver installed"
        ui_msgbox "Success" "fd $latest_ver installed"
    else
        ui_msgbox "Error" "Failed to download fd"
        return 1
    fi
}

# Install ripgrep
install_ripgrep() {
    if ! require_root; then
        return 1
    fi

    if is_installed rg; then
        if ! ui_yesno "Already Installed" "ripgrep is already installed.\n\nReinstall/Update?"; then
            return 0
        fi
    fi

    if ! has_internet; then
        ui_msgbox "Error" "Internet connection required"
        return 1
    fi

    ui_infobox "Installing" "Installing ripgrep..."

    # Get latest version
    local latest_ver
    latest_ver=$(curl -fsSL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest | jq -r .tag_name)

    if [[ -z "$latest_ver" ]]; then
        ui_msgbox "Error" "Failed to get latest version"
        return 1
    fi

    local arch
    arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        arch="x86_64-unknown-linux-musl"
    elif [[ "$arch" == "aarch64" ]]; then
        arch="aarch64-unknown-linux-gnu"
    fi

    local url="https://github.com/BurntSushi/ripgrep/releases/download/${latest_ver}/ripgrep-${latest_ver}-${arch}.tar.gz"

    cd /tmp
    if curl -fsSL "$url" -o ripgrep.tar.gz; then
        tar xzf ripgrep.tar.gz
        cp "ripgrep-${latest_ver}-${arch}/rg" /usr/local/bin/
        rm -rf ripgrep.tar.gz "ripgrep-${latest_ver}-${arch}"
        log_info "ripgrep $latest_ver installed"
        ui_msgbox "Success" "ripgrep $latest_ver installed"
    else
        ui_msgbox "Error" "Failed to download ripgrep"
        return 1
    fi
}

# Install fzf
install_fzf() {
    if ! require_root; then
        return 1
    fi

    if is_installed fzf; then
        if ! ui_yesno "Already Installed" "fzf is already installed.\n\nReinstall/Update?"; then
            return 0
        fi
    fi

    if ! has_internet; then
        ui_msgbox "Error" "Internet connection required"
        return 1
    fi

    ui_infobox "Installing" "Installing fzf..."

    # Get latest version
    local latest_ver
    latest_ver=$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest | jq -r .tag_name | tr -d 'v')

    if [[ -z "$latest_ver" ]]; then
        ui_msgbox "Error" "Failed to get latest version"
        return 1
    fi

    local arch
    arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        arch="amd64"
    elif [[ "$arch" == "aarch64" ]]; then
        arch="arm64"
    fi

    local url="https://github.com/junegunn/fzf/releases/download/v${latest_ver}/fzf-${latest_ver}-linux_${arch}.tar.gz"

    cd /tmp
    if curl -fsSL "$url" -o fzf.tar.gz; then
        tar xzf fzf.tar.gz
        mv fzf /usr/local/bin/
        rm -f fzf.tar.gz
        log_info "fzf $latest_ver installed"
        ui_msgbox "Success" "fzf $latest_ver installed"
    else
        ui_msgbox "Error" "Failed to download fzf"
        return 1
    fi
}

# Install yq
install_yq() {
    if ! require_root; then
        return 1
    fi

    if is_installed yq; then
        local current_ver
        current_ver=$(yq --version 2>/dev/null | awk '{print $NF}')
        if ! ui_yesno "Already Installed" "yq $current_ver is already installed.\n\nReinstall/Update?"; then
            return 0
        fi
    fi

    if ! has_internet; then
        ui_msgbox "Error" "Internet connection required"
        return 1
    fi

    ui_infobox "Installing" "Installing yq..."

    # Get latest version
    local latest_ver
    latest_ver=$(curl -fsSL https://api.github.com/repos/mikefarah/yq/releases/latest | jq -r .tag_name)

    if [[ -z "$latest_ver" ]]; then
        ui_msgbox "Error" "Failed to get latest version"
        return 1
    fi

    local arch
    arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        arch="amd64"
    elif [[ "$arch" == "aarch64" ]]; then
        arch="arm64"
    fi

    local url="https://github.com/mikefarah/yq/releases/download/${latest_ver}/yq_linux_${arch}"

    if curl -fsSL "$url" -o /usr/local/bin/yq; then
        chmod +x /usr/local/bin/yq
        log_info "yq $latest_ver installed"
        ui_msgbox "Success" "yq $latest_ver installed"
    else
        ui_msgbox "Error" "Failed to download yq"
        return 1
    fi
}

# Install starship prompt
install_starship() {
    if ! require_root; then
        return 1
    fi

    if is_installed starship; then
        if ! ui_yesno "Already Installed" "starship is already installed.\n\nReinstall/Update?"; then
            return 0
        fi
    fi

    if ! has_internet; then
        ui_msgbox "Error" "Internet connection required"
        return 1
    fi

    ui_infobox "Installing" "Installing starship..."

    # Use official install script
    if curl -fsSL https://starship.rs/install.sh | sh -s -- -y 2>&1; then
        log_info "starship installed"
        ui_msgbox "Success" "starship installed successfully\n\nAdd to your ~/.bashrc:\neval \"\$(starship init bash)\""
    else
        ui_msgbox "Error" "Failed to install starship"
        return 1
    fi
}

# Uninstall software
uninstall_software() {
    if ! require_root; then
        return 1
    fi

    # Build list of installed software
    local pkg_list=()

    is_installed lazydocker && pkg_list+=("lazydocker" "Docker TUI" "off")
    is_installed lazygit && pkg_list+=("lazygit" "Git TUI" "off")
    is_installed btop && pkg_list+=("btop" "Resource monitor" "off")
    is_installed bat && pkg_list+=("bat" "Better cat" "off")
    is_installed fd && pkg_list+=("fd" "Better find" "off")
    is_installed rg && pkg_list+=("ripgrep" "Better grep" "off")
    is_installed fzf && pkg_list+=("fzf" "Fuzzy finder" "off")
    is_installed yq && pkg_list+=("yq" "YAML processor" "off")
    is_installed starship && pkg_list+=("starship" "Cross-shell prompt" "off")

    if [[ ${#pkg_list[@]} -eq 0 ]]; then
        ui_msgbox "Info" "No removable software installed"
        return 0
    fi

    local selected
    selected=$(ui_checklist "Uninstall Software" "Select software to remove:" "${pkg_list[@]}") || return

    if [[ -z "$selected" ]]; then
        return
    fi

    for pkg in $selected; do
        pkg=$(echo "$pkg" | tr -d '"')
        case "$pkg" in
            lazydocker) rm -f /usr/local/bin/lazydocker ;;
            lazygit)    rm -f /usr/local/bin/lazygit ;;
            btop)       rm -rf /usr/local/bin/btop /usr/local/share/btop ;;
            bat)        rm -f /usr/local/bin/bat ;;
            fd)         rm -f /usr/local/bin/fd ;;
            ripgrep)    rm -f /usr/local/bin/rg ;;
            fzf)        rm -f /usr/local/bin/fzf ;;
            yq)         rm -f /usr/local/bin/yq ;;
            starship)   rm -f /usr/local/bin/starship ;;
        esac
        log_info "Uninstalled: $pkg"
    done

    ui_msgbox "Success" "Selected software has been removed"
}

# Update all installed software
update_all() {
    if ! require_root; then
        return 1
    fi

    if ! has_internet; then
        ui_msgbox "Error" "Internet connection required"
        return 1
    fi

    local to_update=""
    is_installed rclone && to_update+="rclone "
    is_installed lazydocker && to_update+="lazydocker "
    is_installed lazygit && to_update+="lazygit "
    is_installed btop && to_update+="btop "
    is_installed bat && to_update+="bat "
    is_installed fd && to_update+="fd "
    is_installed rg && to_update+="ripgrep "
    is_installed fzf && to_update+="fzf "
    is_installed yq && to_update+="yq "
    is_installed starship && to_update+="starship "

    if [[ -z "$to_update" ]]; then
        ui_msgbox "Info" "No software installed to update"
        return 0
    fi

    if ! ui_yesno "Update All" "Update all installed software?\n\n$to_update"; then
        return
    fi

    # Update each package silently (no individual prompts)
    for pkg in $to_update; do
        ui_infobox "Updating" "Updating $pkg..."
        case "$pkg" in
            rclone)
                curl -fsSL https://rclone.org/install.sh | bash &>/dev/null
                ;;
            lazydocker)
                curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash &>/dev/null
                [[ -f "$HOME/.local/bin/lazydocker" ]] && mv "$HOME/.local/bin/lazydocker" /usr/local/bin/
                ;;
            lazygit)
                local ver=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r .tag_name | tr -d 'v')
                local arch=$(uname -m); [[ "$arch" == "x86_64" ]] && arch="x86_64" || arch="arm64"
                curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_${arch}.tar.gz" -o /tmp/lazygit.tar.gz
                tar xzf /tmp/lazygit.tar.gz -C /tmp lazygit && mv /tmp/lazygit /usr/local/bin/ && rm -f /tmp/lazygit.tar.gz
                ;;
            btop)
                local ver=$(curl -fsSL https://api.github.com/repos/aristocratos/btop/releases/latest | jq -r .tag_name | tr -d 'v')
                curl -fsSL "https://github.com/aristocratos/btop/releases/download/v${ver}/btop-$(uname -m)-linux-musl.tbz" -o /tmp/btop.tbz
                tar xjf /tmp/btop.tbz -C /tmp && cd /tmp/btop && make install PREFIX=/usr/local &>/dev/null && cd /tmp && rm -rf btop btop.tbz
                ;;
            bat)
                local ver=$(curl -fsSL https://api.github.com/repos/sharkdp/bat/releases/latest | jq -r .tag_name | tr -d 'v')
                local arch=$(uname -m); [[ "$arch" == "x86_64" ]] && arch="x86_64-unknown-linux-musl" || arch="aarch64-unknown-linux-gnu"
                curl -fsSL "https://github.com/sharkdp/bat/releases/download/v${ver}/bat-v${ver}-${arch}.tar.gz" -o /tmp/bat.tar.gz
                tar xzf /tmp/bat.tar.gz -C /tmp && cp "/tmp/bat-v${ver}-${arch}/bat" /usr/local/bin/ && rm -rf /tmp/bat.tar.gz "/tmp/bat-v${ver}-${arch}"
                ;;
            fd)
                local ver=$(curl -fsSL https://api.github.com/repos/sharkdp/fd/releases/latest | jq -r .tag_name | tr -d 'v')
                local arch=$(uname -m); [[ "$arch" == "x86_64" ]] && arch="x86_64-unknown-linux-musl" || arch="aarch64-unknown-linux-gnu"
                curl -fsSL "https://github.com/sharkdp/fd/releases/download/v${ver}/fd-v${ver}-${arch}.tar.gz" -o /tmp/fd.tar.gz
                tar xzf /tmp/fd.tar.gz -C /tmp && cp "/tmp/fd-v${ver}-${arch}/fd" /usr/local/bin/ && rm -rf /tmp/fd.tar.gz "/tmp/fd-v${ver}-${arch}"
                ;;
            ripgrep)
                local ver=$(curl -fsSL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest | jq -r .tag_name)
                local arch=$(uname -m); [[ "$arch" == "x86_64" ]] && arch="x86_64-unknown-linux-musl" || arch="aarch64-unknown-linux-gnu"
                curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/${ver}/ripgrep-${ver}-${arch}.tar.gz" -o /tmp/rg.tar.gz
                tar xzf /tmp/rg.tar.gz -C /tmp && cp "/tmp/ripgrep-${ver}-${arch}/rg" /usr/local/bin/ && rm -rf /tmp/rg.tar.gz "/tmp/ripgrep-${ver}-${arch}"
                ;;
            fzf)
                local ver=$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest | jq -r .tag_name | tr -d 'v')
                local arch=$(uname -m); [[ "$arch" == "x86_64" ]] && arch="amd64" || arch="arm64"
                curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${ver}/fzf-${ver}-linux_${arch}.tar.gz" -o /tmp/fzf.tar.gz
                tar xzf /tmp/fzf.tar.gz -C /tmp && mv /tmp/fzf /usr/local/bin/ && rm -f /tmp/fzf.tar.gz
                ;;
            yq)
                local ver=$(curl -fsSL https://api.github.com/repos/mikefarah/yq/releases/latest | jq -r .tag_name)
                local arch=$(uname -m); [[ "$arch" == "x86_64" ]] && arch="amd64" || arch="arm64"
                curl -fsSL "https://github.com/mikefarah/yq/releases/download/${ver}/yq_linux_${arch}" -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq
                ;;
            starship)
                curl -fsSL https://starship.rs/install.sh | sh -s -- -y &>/dev/null
                ;;
        esac
        log_info "Updated: $pkg"
    done

    ui_msgbox "Complete" "All software has been updated"
}

# Install multiple software
install_multiple() {
    if ! require_root; then
        return 1
    fi

    # Build checklist excluding installed software
    local pkg_list=()

    if ! is_installed rclone; then
        pkg_list+=("rclone" "Cloud storage sync tool" "off")
    fi
    if ! is_installed lazydocker; then
        pkg_list+=("lazydocker" "Docker TUI" "off")
    fi
    if ! is_installed lazygit; then
        pkg_list+=("lazygit" "Git TUI" "off")
    fi
    if ! is_installed btop; then
        pkg_list+=("btop" "Resource monitor (better htop)" "off")
    fi
    if ! is_installed bat; then
        pkg_list+=("bat" "Better cat with syntax highlighting" "off")
    fi
    if ! is_installed fd; then
        pkg_list+=("fd" "Better find" "off")
    fi
    if ! is_installed rg; then
        pkg_list+=("ripgrep" "Better grep" "off")
    fi
    if ! is_installed fzf; then
        pkg_list+=("fzf" "Fuzzy finder" "off")
    fi
    if ! is_installed yq; then
        pkg_list+=("yq" "YAML processor" "off")
    fi
    if ! is_installed starship; then
        pkg_list+=("starship" "Cross-shell prompt" "off")
    fi

    if [[ ${#pkg_list[@]} -eq 0 ]]; then
        ui_msgbox "All Installed" "All available software is already installed."
        return 0
    fi

    local selected
    selected=$(ui_checklist "Install Software" "Select software to install:" "${pkg_list[@]}") || return

    if [[ -z "$selected" ]]; then
        return
    fi

    # Install selected software
    for pkg in $selected; do
        pkg=$(echo "$pkg" | tr -d '"')
        case "$pkg" in
            rclone)         install_rclone ;;
            lazydocker)     install_lazydocker ;;
            lazygit)        install_lazygit ;;
            btop)           install_btop ;;
            bat)            install_bat ;;
            fd)             install_fd ;;
            ripgrep)        install_ripgrep ;;
            fzf)            install_fzf ;;
            yq)             install_yq ;;
            starship)       install_starship ;;
        esac
    done
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "Software" "Select operation:" \
            "status" "Show installation status" \
            "install" "Install software" \
            "uninstall" "Uninstall software" \
            "update-all" "Update all installed") || break

        case "$choice" in
            status)     show_status ;;
            install)    install_multiple ;;
            uninstall)  uninstall_software ;;
            update-all) update_all ;;
        esac
    done
}
