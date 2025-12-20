# Features

Complete list of all modules and their features.

## APT Manager

Manage and maintain APT packages and updates.

- **Check and install updates** - Shows all available updates in a checklist (preselected), allows selective updates
- **Update package lists** - Run apt update
- **Install common packages** - Curated list of useful packages (hides already installed)
- **Install package** - Install by name
- **Remove package** - With option to purge configs
- **Search packages** - Search apt cache
- **Show package info** - Display package details
- **List installed packages** - With optional filter
- **Clean up APT cache** - autoremove, autoclean, clean
- **Fix broken packages** - dpkg --configure and --fix-broken
- **Add PPA repository**
- **Show cache info** - Cache size, package counts
- **Show APT history**

## CrowdSec

Install and manage CrowdSec IDS/IPS (Intrusion Detection and Prevention System).

- **Quick setup** - Install common protection collections and firewall bouncer with checklist:
  - crowdsecurity/linux (base OS protection)
  - crowdsecurity/sshd (SSH brute force)
  - crowdsecurity/http-cve (HTTP exploits)
  - crowdsecurity/base-http-scenarios (HTTP attacks)
  - crowdsecurity/nginx (Nginx protection)
  - crowdsecurity/apache2 (Apache protection)
  - Firewall bouncer installation option
- **Show CrowdSec status** - Service status, version, scenarios/collections/decisions/bouncers counts, hub status
- **Show active decisions** - List all current bans with IP, reason, duration, scenario, type
- **Install/Uninstall CrowdSec** - With automatic Quick Setup wizard after installation
- **Service control** - Start, stop, restart, reload, show systemd status
- **View logs** - Service logs (journalctl), decision logs, log file
- **Ban IP manually** - Add custom ban with:
  - IP validation
  - Duration (4h, 2d, 1w, 0 for permanent)
  - Ban type (ban, captcha, throttle)
  - Custom reason
- **Unban IP** - Remove specific IP ban
- **Clear all bans** - Remove all active decisions with confirmation
- **Manage whitelist** - Show, add, remove whitelisted IPs (never banned)
- **Show installed scenarios** - List all scenarios with status
- **Manage collections** - List, install, remove, update hub index, upgrade all items
- **Manage bouncers** - List, install firewall bouncer, add custom bouncer (get API key), remove
- **Console enrollment** - Enroll to CrowdSec Console (cloud management) and show status
- **Manage parsers** - List, install, remove, upgrade parsers
- **Manage postoverflows** - List, install, remove postoverflows
- **Acquisition configuration** - View, edit, test log source configuration
- **Toggle simulation mode** - Enable/disable simulation (test scenarios without real bans)
- **Explain decision for IP** - Show why an IP was banned (decisions, alerts, timeline)

## Docker Install

Install and manage Docker CE.

- Install Docker CE
- Uninstall Docker
- Show Docker status
- Add user to docker group
- Configure Docker daemon

## Fail2ban

Install and configure fail2ban intrusion prevention.

- **Quick setup** - Install and enable common jails
- **Show status** - Overall fail2ban status
- **Show statistics** - Ban counts per jail
- **Show jail status** - Individual jail details
- **Show banned IPs** - All banned IPs per jail
- **Install/Uninstall fail2ban**
- **Configure defaults** - Ban time, find time, max retries, ban action, email
- **Enable jail** - SSH, Apache, Nginx, Postfix, Dovecot, MySQL, custom
- **Disable jail**
- **Ban/Unban IP manually**
- **Clear all bans** - Unban all IPs from all jails
- **Whitelist IP** - Never ban specific IPs
- **View log**
- **Restart service**

## Hostname Manager

Configure system hostname and related settings.

- **Show hostname information** - Current hostname, FQDN, hostnamectl status, /etc/hosts
- **Set hostname** - With validation, option for all/static/transient/pretty
- **Set pretty hostname** - Human-readable name
- **Edit /etc/hosts** - View, add, remove, edit entries
- **Set chassis type** - desktop, laptop, server, VM, container, etc.
- **Set deployment environment** - development, integration, staging, production
- **Set location** - Physical location description
- **Set icon name**

## NTP Client

Configure time synchronization using systemd-timesyncd.

- **Quick setup** - Configure pool, timezone, enable sync
- **Show status** - Current time sync status
- **Configure NTP servers** - Global pools or country-specific (ntppool.org)
  - Regions: Global, Africa, Asia, Europe, North America, South America, Oceania
  - Countries: 60+ countries available
- **Configure timezone** - Browse by region
- **Enable/Disable NTP sync**
- **Force time sync**
- **Set time manually**

## Network Manager

Configure network interfaces using netplan.

- **Show network status** - Interface info, IP addresses, routes, DNS
- **Test connectivity** - DNS, ping, and HTTP tests
- **Show routing table** - IPv4 and IPv6 routes
- **Quick setup** - Guided interface configuration
- **Configure IPv4** - DHCP, static IP, or disable
- **Configure IPv6** - Auto (SLAAC), DHCPv6, static IP, or disable
- **Add static route** - Temporary route via gateway
- **View DNS configuration** - Show resolv.conf
- **Disable IPv6 system-wide** - Via sysctl (affects all interfaces)
- **Enable IPv6 system-wide** - Remove sysctl disable
- **Show netplan config** - Display current netplan YAML
- **Apply netplan** - Apply configuration changes
- **Restart networking** - Restart systemd-networkd

## Software Installer

Install software not available via APT.

- **Show installation status**
- **Install multiple software** - Checklist (hides already installed)
- **Update all installed** - Update all installed software at once
- **Uninstall software** - Remove installed software
- Available software:
  - **rclone** - Cloud storage sync tool
  - **lazydocker** - Docker TUI
  - **lazygit** - Git TUI
  - **btop** - Better resource monitor
  - **bat** - Better cat with syntax highlighting
  - **fd** - Better find
  - **ripgrep** - Better grep
  - **fzf** - Fuzzy finder
  - **yq** - YAML processor
  - **starship** - Cross-shell prompt

## MOTD Manager

Configure system Message of the Day banner.

- **Show status** - Banner installation status
- **Show current MOTD** - Preview generated MOTD
- **Install MOTD banner** - ASCII art hostname with figlet, system info, font selection, static/pretty hostname option
- **Remove MOTD banner**
- **Manage MOTD scripts** - Enable/disable scripts in /etc/update-motd.d

## SSH Manager

Configure SSH server settings and security.

- **Show SSH status**
- **Install colored prompt** - Format: username@pretty-hostname /path $ (Username=Red/Green, @=Yellow, Hostname=Light Blue, Path=Yellow)
- **Remove colored prompt**
- **Change SSH port**
- **Configure root login** - keys only, password, disabled, forced-commands-only
- **Configure password authentication**
- **Harden SSH** - Apply security best practices:
  - Disable root password login
  - Disable password authentication (keys only)
  - Disable empty passwords
  - Disable X11 forwarding
  - Max 3 auth tries
  - 60s login grace time
  - Disable TCP forwarding
  - Strict modes
  - Client alive timeout
- **Advanced settings** - X11, TCP forwarding, compression, banner, timeout
- **Manage SSH keys** - List, add, generate, remove authorized keys
- **Restart SSH service**

## System Info

Display system information.

- Show system overview
- CPU information
- Memory information
- Disk usage
- Network information
- Hardware information
- System temperatures
- Export system report

## VM Guest Agents

Install guest agents for virtual environments.

- **Detect virtualization** - Auto-detect hypervisor environment
- **Show status** - Installation status of all guest agents
- **VMware Tools** - For VMware ESXi, Workstation, Fusion (open-vm-tools)
- **QEMU Guest Agent** - For Proxmox, KVM, QEMU, libvirt
- **VirtualBox Guest Additions** - For Oracle VirtualBox
- **Hyper-V Daemons** - For Microsoft Hyper-V
- **Xen Tools** - For Citrix XenServer, XCP-ng

## UFW Docker

Configure UFW to work properly with Docker (ufw-docker).

- **Install ufw-docker** - Fixes Docker bypassing UFW
- **Uninstall ufw-docker**
- **Show status**
- **Allow container port**
- **Delete container rule**

## UFW Manager

Manage UFW firewall rules and settings.

- **Install UFW**
- **Show UFW status**
- **Enable/Disable UFW**
- **Add allow rule** - By port, service, IP, subnet
- **Add deny rule** - By port, IP, subnet
- **Delete rule** - By rule number
- **Set default policies** - incoming/outgoing
- **Quick setup** - Common services (SSH, HTTP, HTTPS, MySQL, PostgreSQL, etc.)
- **Reset UFW**

## Unattended Upgrades

Configure automatic system updates.

- **Show status**
- **Enable/Disable unattended upgrades**
- **Configure automatic reboot** - Enable, disable, set time
- **Configure remove unused dependencies**
- **Configure update origins** - Security, updates, proposed, backports
- **Run unattended-upgrade now**

## User Management

Manage system users and groups.

- **Add new user** - With password, groups selection
- **Modify user groups**
- **Delete user** - With option to remove home directory
- **View user information** - Details or list all users
