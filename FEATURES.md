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
- **Show jail status** - Individual jail details
- **Show banned IPs** - All banned IPs per jail
- **Install/Uninstall fail2ban**
- **Configure defaults** - Ban time, find time, max retries, ban action, email
- **Enable jail** - SSH, Apache, Nginx, Postfix, Dovecot, MySQL, custom
- **Disable jail**
- **Ban/Unban IP manually**
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

## Software Installer

Install software not available via APT.

- **Show installation status**
- **Install multiple software** - Checklist (hides already installed)
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

## SSH Manager

Configure SSH server, MOTD, and shell prompt.

- **Show SSH status**
- **Show current MOTD**
- **Install MOTD banner** - ASCII art hostname with figlet, system info, font preview
- **Remove MOTD banner**
- **Install colored prompt** - Root=Red, Users=Green, Path=Blue
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
