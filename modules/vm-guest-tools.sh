#!/bin/bash
#
# VM Guest Agents Module
# Install guest agents for various virtualization platforms
#

# Module metadata
module_info() {
    echo "VM Guest Agents|Install guest agents for virtual environments"
}

# Detect virtualization environment
detect_virtualization() {
    local info=""
    info+="=== Virtualization Detection ===\n\n"

    local detected=""
    local hypervisor=""

    # Check systemd-detect-virt
    if command_exists systemd-detect-virt; then
        hypervisor=$(systemd-detect-virt 2>/dev/null)
        if [[ -n "$hypervisor" && "$hypervisor" != "none" ]]; then
            detected="$hypervisor"
        fi
    fi

    # Check DMI/SMBIOS for vendor info
    if [[ -z "$detected" && -r /sys/class/dmi/id/sys_vendor ]]; then
        local vendor
        vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
        case "$vendor" in
            *VMware*)     detected="vmware" ;;
            *QEMU*)       detected="qemu" ;;
            *KVM*)        detected="kvm" ;;
            *Microsoft*)  detected="microsoft" ;;
            *Xen*)        detected="xen" ;;
            *innotek*|*VirtualBox*) detected="virtualbox" ;;
            *Parallels*)  detected="parallels" ;;
        esac
    fi

    # Check product name
    if [[ -z "$detected" && -r /sys/class/dmi/id/product_name ]]; then
        local product
        product=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
        case "$product" in
            *VMware*)     detected="vmware" ;;
            *Virtual\ Machine*) detected="hyperv" ;;
            *KVM*)        detected="kvm" ;;
            *VirtualBox*) detected="virtualbox" ;;
        esac
    fi

    # Check for specific files/devices
    if [[ -z "$detected" ]]; then
        [[ -d /proc/xen ]] && detected="xen"
        [[ -e /dev/vmci ]] && detected="vmware"
        [[ -e /dev/vboxguest ]] && detected="virtualbox"
    fi

    if [[ -n "$detected" ]]; then
        info+="Detected Environment: $detected\n\n"

        case "$detected" in
            vmware)
                info+="Platform: VMware (ESXi, Workstation, Fusion)\n"
                info+="Recommended: open-vm-tools\n"
                ;;
            qemu|kvm)
                info+="Platform: QEMU/KVM (Proxmox, libvirt, etc.)\n"
                info+="Recommended: qemu-guest-agent\n"
                ;;
            virtualbox|oracle)
                info+="Platform: VirtualBox\n"
                info+="Recommended: virtualbox-guest-utils\n"
                ;;
            microsoft|hyperv)
                info+="Platform: Microsoft Hyper-V\n"
                info+="Recommended: linux-cloud-tools-virtual\n"
                ;;
            xen)
                info+="Platform: Xen\n"
                info+="Recommended: xe-guest-utilities\n"
                ;;
            parallels)
                info+="Platform: Parallels Desktop\n"
                info+="Recommended: Install from Parallels Tools ISO\n"
                ;;
            *)
                info+="Platform: $detected\n"
                info+="Please select appropriate guest agent manually.\n"
                ;;
        esac
    else
        info+="No virtualization detected.\n\n"
        info+="This system appears to be running on bare metal,\n"
        info+="or the virtualization platform could not be identified.\n"
    fi

    echo -e "$info" > /tmp/virt_detect.txt
    ui_textbox "Virtualization Detection" /tmp/virt_detect.txt
    rm -f /tmp/virt_detect.txt
}

# Show installation status
show_status() {
    local info=""
    info+="=== Guest Agent Status ===\n\n"

    # VMware
    if package_installed open-vm-tools; then
        local status="Installed"
        service_is_running vmtoolsd && status+=" (Running)"
        info+="VMware Tools:      $status\n"
    else
        info+="VMware Tools:      Not installed\n"
    fi

    # QEMU Guest Agent
    if package_installed qemu-guest-agent; then
        local status="Installed"
        service_is_running qemu-guest-agent && status+=" (Running)"
        info+="QEMU Guest Agent:  $status\n"
    else
        info+="QEMU Guest Agent:  Not installed\n"
    fi

    # VirtualBox
    if package_installed virtualbox-guest-utils; then
        info+="VirtualBox Guest:  Installed\n"
    else
        info+="VirtualBox Guest:  Not installed\n"
    fi

    # Hyper-V
    if package_installed linux-cloud-tools-virtual; then
        info+="Hyper-V Daemons:   Installed\n"
    else
        info+="Hyper-V Daemons:   Not installed\n"
    fi

    # Xen
    if package_installed xe-guest-utilities; then
        info+="Xen Tools:         Installed\n"
    else
        info+="Xen Tools:         Not installed\n"
    fi

    echo -e "$info" > /tmp/guest_status.txt
    ui_textbox "Guest Agent Status" /tmp/guest_status.txt
    rm -f /tmp/guest_status.txt
}

# Install VMware Tools
install_vmware_tools() {
    if ! require_root; then
        return 1
    fi

    if package_installed open-vm-tools; then
        if ! ui_yesno "Already Installed" "VMware Tools (open-vm-tools) is already installed.\n\nReinstall?"; then
            return 0
        fi
    fi

    local packages="open-vm-tools"

    # Ask about desktop integration
    if ui_yesno "Desktop Support" "Install desktop integration?\n\n(For GUI systems with VMware features like drag-and-drop)"; then
        packages+=" open-vm-tools-desktop"
    fi

    ui_infobox "Installing" "Installing VMware Tools..."

    if install_packages $packages; then
        systemctl enable vmtoolsd
        systemctl start vmtoolsd
        log_info "VMware Tools installed"
        ui_msgbox "Success" "VMware Tools installed successfully.\n\nService vmtoolsd is now running."
    else
        ui_msgbox "Error" "Failed to install VMware Tools"
        return 1
    fi
}

# Uninstall VMware Tools
uninstall_vmware_tools() {
    if ! require_root; then
        return 1
    fi

    if ! package_installed open-vm-tools; then
        ui_msgbox "Info" "VMware Tools is not installed"
        return 0
    fi

    if ui_yesno "Uninstall" "Remove VMware Tools?"; then
        systemctl stop vmtoolsd 2>/dev/null
        remove_packages open-vm-tools open-vm-tools-desktop
        log_info "VMware Tools uninstalled"
        ui_msgbox "Success" "VMware Tools removed"
    fi
}

# Install QEMU Guest Agent
install_qemu_agent() {
    if ! require_root; then
        return 1
    fi

    if package_installed qemu-guest-agent; then
        if ! ui_yesno "Already Installed" "QEMU Guest Agent is already installed.\n\nReinstall?"; then
            return 0
        fi
    fi

    ui_infobox "Installing" "Installing QEMU Guest Agent..."

    if install_packages qemu-guest-agent; then
        systemctl enable qemu-guest-agent
        systemctl start qemu-guest-agent
        log_info "QEMU Guest Agent installed"
        ui_msgbox "Success" "QEMU Guest Agent installed successfully.\n\nService is now running.\n\nNote: Ensure the guest agent channel is enabled in your hypervisor."
    else
        ui_msgbox "Error" "Failed to install QEMU Guest Agent"
        return 1
    fi
}

# Uninstall QEMU Guest Agent
uninstall_qemu_agent() {
    if ! require_root; then
        return 1
    fi

    if ! package_installed qemu-guest-agent; then
        ui_msgbox "Info" "QEMU Guest Agent is not installed"
        return 0
    fi

    if ui_yesno "Uninstall" "Remove QEMU Guest Agent?"; then
        systemctl stop qemu-guest-agent 2>/dev/null
        remove_packages qemu-guest-agent
        log_info "QEMU Guest Agent uninstalled"
        ui_msgbox "Success" "QEMU Guest Agent removed"
    fi
}

# Install VirtualBox Guest Additions
install_virtualbox_guest() {
    if ! require_root; then
        return 1
    fi

    if package_installed virtualbox-guest-utils; then
        if ! ui_yesno "Already Installed" "VirtualBox Guest Additions is already installed.\n\nReinstall?"; then
            return 0
        fi
    fi

    local packages="virtualbox-guest-utils"

    # Ask about X11 support
    if ui_yesno "X11 Support" "Install X11 guest additions?\n\n(For GUI systems with shared clipboard, seamless mode, etc.)"; then
        packages+=" virtualbox-guest-x11"
    fi

    ui_infobox "Installing" "Installing VirtualBox Guest Additions..."

    if install_packages $packages; then
        log_info "VirtualBox Guest Additions installed"
        ui_msgbox "Success" "VirtualBox Guest Additions installed.\n\nA reboot is recommended for full functionality."
    else
        ui_msgbox "Error" "Failed to install VirtualBox Guest Additions"
        return 1
    fi
}

# Uninstall VirtualBox Guest Additions
uninstall_virtualbox_guest() {
    if ! require_root; then
        return 1
    fi

    if ! package_installed virtualbox-guest-utils; then
        ui_msgbox "Info" "VirtualBox Guest Additions is not installed"
        return 0
    fi

    if ui_yesno "Uninstall" "Remove VirtualBox Guest Additions?"; then
        remove_packages virtualbox-guest-utils virtualbox-guest-x11
        log_info "VirtualBox Guest Additions uninstalled"
        ui_msgbox "Success" "VirtualBox Guest Additions removed"
    fi
}

# Install Hyper-V daemons
install_hyperv_daemons() {
    if ! require_root; then
        return 1
    fi

    if package_installed linux-cloud-tools-virtual; then
        if ! ui_yesno "Already Installed" "Hyper-V daemons are already installed.\n\nReinstall?"; then
            return 0
        fi
    fi

    ui_infobox "Installing" "Installing Hyper-V integration services..."

    if install_packages linux-cloud-tools-virtual linux-tools-virtual; then
        # Enable Hyper-V services
        systemctl enable hv_fcopy_daemon 2>/dev/null
        systemctl enable hv_kvp_daemon 2>/dev/null
        systemctl enable hv_vss_daemon 2>/dev/null
        systemctl start hv_fcopy_daemon 2>/dev/null
        systemctl start hv_kvp_daemon 2>/dev/null
        systemctl start hv_vss_daemon 2>/dev/null

        log_info "Hyper-V daemons installed"
        ui_msgbox "Success" "Hyper-V integration services installed.\n\nServices are now running."
    else
        ui_msgbox "Error" "Failed to install Hyper-V daemons"
        return 1
    fi
}

# Uninstall Hyper-V daemons
uninstall_hyperv_daemons() {
    if ! require_root; then
        return 1
    fi

    if ! package_installed linux-cloud-tools-virtual; then
        ui_msgbox "Info" "Hyper-V daemons are not installed"
        return 0
    fi

    if ui_yesno "Uninstall" "Remove Hyper-V daemons?"; then
        systemctl stop hv_fcopy_daemon hv_kvp_daemon hv_vss_daemon 2>/dev/null
        remove_packages linux-cloud-tools-virtual linux-tools-virtual
        log_info "Hyper-V daemons uninstalled"
        ui_msgbox "Success" "Hyper-V daemons removed"
    fi
}

# Install Xen guest utilities
install_xen_tools() {
    if ! require_root; then
        return 1
    fi

    if package_installed xe-guest-utilities; then
        if ! ui_yesno "Already Installed" "Xen Tools are already installed.\n\nReinstall?"; then
            return 0
        fi
    fi

    ui_infobox "Installing" "Installing Xen guest utilities..."

    if install_packages xe-guest-utilities; then
        log_info "Xen Tools installed"
        ui_msgbox "Success" "Xen guest utilities installed successfully."
    else
        ui_msgbox "Error" "Failed to install Xen Tools"
        return 1
    fi
}

# Uninstall Xen guest utilities
uninstall_xen_tools() {
    if ! require_root; then
        return 1
    fi

    if ! package_installed xe-guest-utilities; then
        ui_msgbox "Info" "Xen Tools are not installed"
        return 0
    fi

    if ui_yesno "Uninstall" "Remove Xen guest utilities?"; then
        remove_packages xe-guest-utilities
        log_info "Xen Tools uninstalled"
        ui_msgbox "Success" "Xen guest utilities removed"
    fi
}

# Main module function
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "VM Guest Agents" "Select operation:" \
            "status" "Show installation status" \
            "detect" "Detect virtualization environment" \
            "qemu" "Install QEMU Guest Agent (Proxmox/KVM/QEMU/libvirt)" \
            "qemu-remove" "Uninstall QEMU Guest Agent" \
            "vmware" "Install VMware Tools (VMware ESXi/Workstation/Fusion)" \
            "vmware-remove" "Uninstall VMware Tools" \
            "vbox" "Install VirtualBox Guest Additions (VirtualBox)" \
            "vbox-remove" "Uninstall VirtualBox Guest Additions" \
            "hyperv" "Install Hyper-V Daemons (Microsoft Hyper-V)" \
            "hyperv-remove" "Uninstall Hyper-V Daemons" \
            "xen" "Install Xen Tools (Citrix XenServer/XCP-ng)" \
            "xen-remove" "Uninstall Xen Tools") || break

        case "$choice" in
            status)        show_status ;;
            detect)        detect_virtualization ;;
            qemu)          install_qemu_agent ;;
            qemu-remove)   uninstall_qemu_agent ;;
            vmware)        install_vmware_tools ;;
            vmware-remove) uninstall_vmware_tools ;;
            vbox)          install_virtualbox_guest ;;
            vbox-remove)   uninstall_virtualbox_guest ;;
            hyperv)        install_hyperv_daemons ;;
            hyperv-remove) uninstall_hyperv_daemons ;;
            xen)           install_xen_tools ;;
            xen-remove)    uninstall_xen_tools ;;
        esac
    done
}
