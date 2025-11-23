# Claude Configuration for Ubuntu Server Manager

This document provides instructions for Claude AI to create new modules for the Ubuntu Server Manager system.

## Important: Documentation Updates

When making changes that affect the project's functionality, features, or structure, **always update the documentation**:

- **README.md** - Update if changing installation, usage, project structure, or general information
- **FEATURES.md** - Update when adding, removing, or modifying module features

This ensures the documentation stays in sync with the actual codebase.

## Project Structure

```
ubuntu-scripts/
├── server-manager.sh      # Main entry point
├── lib/
│   ├── ui.sh              # Dialog-based UI helper functions
│   └── common.sh          # Common utility functions
├── modules/
│   ├── apt.sh             # APT package management
│   ├── docker.sh          # Docker installation
│   ├── fail2ban.sh        # Fail2ban configuration
│   ├── hostname.sh        # Hostname configuration
│   ├── motd.sh            # MOTD banner configuration
│   ├── network.sh         # Network interface management
│   ├── ntp-client.sh      # NTP time synchronization
│   ├── software.sh        # Non-APT software installation
│   ├── ssh.sh             # SSH server configuration
│   ├── system-info.sh     # System information
│   ├── ufw.sh             # UFW firewall management
│   ├── ufw-docker.sh      # UFW Docker integration
│   ├── unattended-upgrades.sh # Automatic updates
│   ├── user.sh            # User management
│   └── vm-guest.sh        # VM guest agent installation
└── CLAUDE.md              # This file
```

## Creating a New Module

### Module Template

Create a new file in the `modules/` directory with a `.sh` extension:

```bash
#!/bin/bash
#
# Module Name - Brief description
# Detailed description of what this module does
#

# Module metadata - REQUIRED
# Format: "Display Name|Description for menu"
module_info() {
    echo "Module Name|Short description shown in main menu"
}

# Module main function - REQUIRED
# This is called when the module is selected from the main menu
module_main() {
    while true; do
        local choice
        choice=$(ui_menu "Module Title" "Select operation:" \
            "action1" "Description of action 1" \
            "action2" "Description of action 2") || break

        case "$choice" in
            action1) do_action1 ;;
            action2) do_action2 ;;
        esac
    done
}

# Implement your action functions here
do_action1() {
    # Your code here
}
```

## Available UI Functions (from lib/ui.sh)

### Message Dialogs

```bash
# Show a message box (blocking, requires OK)
ui_msgbox "Title" "Message text"

# Show an info box (non-blocking, disappears)
ui_infobox "Title" "Message text"

# Show yes/no dialog (returns 0 for yes, 1 for no)
if ui_yesno "Title" "Question?"; then
    echo "User said yes"
fi
```

### Input Functions

```bash
# Text input
result=$(ui_inputbox "Title" "Enter value:" "default_value")

# Password input (masked)
password=$(ui_passwordbox "Title" "Enter password:")

# Date picker
date=$(ui_calendar "Select Date" 1 1 2024)  # day month year

# Time picker
time=$(ui_timebox "Select Time" 12 30 0)  # hour minute second
```

### Selection Functions

```bash
# Single selection menu
choice=$(ui_menu "Title" "Select one:" \
    "tag1" "Description 1" \
    "tag2" "Description 2")

# Multiple selection checklist
# Third parameter per item: "on" or "off" for default state
choices=$(ui_checklist "Title" "Select multiple:" \
    "item1" "Description 1" "off" \
    "item2" "Description 2" "on")

# Radio button list (single selection from toggle items)
choice=$(ui_radiolist "Title" "Select one:" \
    "option1" "Description 1" "on" \
    "option2" "Description 2" "off")
```

### File/Directory Selection

```bash
# Select a file
file=$(ui_fselect "/starting/path")

# Select a directory
dir=$(ui_dselect "/starting/path")
```

### Form Functions

```bash
# Multi-field form
# Arguments: Label y x Value y x fieldlen maxlen
result=$(ui_form "Title" \
    "Username:" 1 1 "" 1 15 20 50 \
    "Email:" 2 1 "" 2 15 30 100)
# Returns values separated by newlines

# Mixed form with password fields
# Last argument per field: 0=normal, 1=hidden, 2=readonly
result=$(ui_mixedform "Title" \
    "Username:" 1 1 "" 1 15 20 50 0 \
    "Password:" 2 1 "" 2 15 20 50 1)
```

### Progress Display

```bash
# Progress gauge (pipe percentage values)
(
    echo 10
    do_something
    echo 50
    do_more
    echo 100
) | ui_gauge "Title" "Processing..."

# Show command output in scrollable box
command_output | ui_progressbox "Title"

# Run command and display output
ui_run_command "Title" command arg1 arg2
```

### Text Display

```bash
# Display file contents
ui_textbox "Title" "/path/to/file"

# Show text in scrollable box
ui_show_output "Title" "Text content here"
```

## Available Helper Functions (from lib/common.sh)

### System Checks

```bash
is_root                    # Check if running as root
require_root               # Require root or show error
command_exists "cmd"       # Check if command exists
package_installed "pkg"    # Check if apt package is installed
```

### Package Management

```bash
install_packages pkg1 pkg2    # Install with progress
remove_packages pkg1 pkg2     # Remove packages
```

### Service Management

```bash
service_start "service"       # Start systemd service
service_stop "service"        # Stop service
service_restart "service"     # Restart service
service_enable "service"      # Enable on boot
service_is_running "service"  # Check if running (returns 0/1)
```

### User Management

```bash
get_regular_users            # List users with UID >= 1000
get_all_groups               # List all system groups
get_user_groups "username"   # List user's groups
user_exists "username"       # Check if user exists
group_exists "groupname"     # Check if group exists
```

### Network Helpers

```bash
get_primary_ip               # Get primary IP address
port_in_use 8080             # Check if port is in use
has_internet                 # Check internet connectivity
```

### File Operations

```bash
backup_file "/path/to/file"  # Create timestamped backup
ensure_dir "/path/to/dir"    # Create directory if missing
download_file "url" "dest"   # Download file (wget/curl)
```

### Validation

```bash
validate_username "user"     # Validate username format
validate_ip "192.168.1.1"    # Validate IP address
validate_port 8080           # Validate port number
```

### Logging

```bash
log_info "Message"           # Log info message
log_warn "Message"           # Log warning
log_error "Message"          # Log error
```

### Formatting

```bash
format_bytes 1073741824      # Returns "1GB"
format_duration 3665         # Returns "1h 1m"
```

## Best Practices

### 1. Always Check Prerequisites

```bash
if ! command_exists docker; then
    ui_msgbox "Error" "Docker is not installed"
    return 1
fi
```

### 2. Require Root When Needed

```bash
if ! require_root; then
    return 1
fi
```

### 3. Confirm Destructive Actions

```bash
if ! ui_yesno "Confirm" "This will delete all data. Continue?"; then
    return
fi
```

### 4. Provide Progress Feedback

```bash
ui_infobox "Working" "Please wait..."
sleep 1

# Or for long operations
(
    echo 0
    do_step_1
    echo 33
    do_step_2
    echo 66
    do_step_3
    echo 100
) | ui_gauge "Installing" "Processing..."
```

### 5. Log Important Actions

```bash
log_info "Created user: $username"
log_error "Failed to install package: $package"
```

### 6. Handle Errors Gracefully

```bash
if ! some_command; then
    ui_msgbox "Error" "Operation failed"
    log_error "some_command failed"
    return 1
fi
```

### 7. Use Loops for Menus

```bash
module_main() {
    while true; do
        choice=$(ui_menu ...) || break  # Exit on cancel
        case "$choice" in
            ...
        esac
    done
}
```

## Example: Creating a Simple Module

Here's a complete example of a backup management module:

```bash
#!/bin/bash
#
# Backup Module - Simple backup management
#

module_info() {
    echo "Backup Manager|Create and manage system backups"
}

create_backup() {
    if ! require_root; then
        return 1
    fi

    # Select directory to backup
    local source
    source=$(ui_dselect "/home") || return

    # Select destination
    local dest
    dest=$(ui_dselect "/backup") || return

    # Get backup name
    local name
    name=$(ui_inputbox "Backup" "Backup name:" "backup_$(date +%Y%m%d)") || return

    # Confirm
    if ! ui_yesno "Confirm" "Backup $source to $dest/$name.tar.gz?"; then
        return
    fi

    # Create backup with progress
    (
        tar -czf "$dest/$name.tar.gz" -C "$(dirname "$source")" "$(basename "$source")" 2>&1
    ) | ui_progressbox "Creating Backup"

    if [[ -f "$dest/$name.tar.gz" ]]; then
        local size
        size=$(du -h "$dest/$name.tar.gz" | cut -f1)
        log_info "Created backup: $dest/$name.tar.gz ($size)"
        ui_msgbox "Success" "Backup created: $dest/$name.tar.gz\nSize: $size"
    else
        log_error "Backup failed: $dest/$name.tar.gz"
        ui_msgbox "Error" "Failed to create backup"
    fi
}

module_main() {
    while true; do
        local choice
        choice=$(ui_menu "Backup Manager" "Select operation:" \
            "create" "Create new backup" \
            "list" "List backups" \
            "restore" "Restore backup") || break

        case "$choice" in
            create) create_backup ;;
            list) list_backups ;;
            restore) restore_backup ;;
        esac
    done
}
```

## Testing Your Module

1. Place your module in the `modules/` directory
2. Make it executable: `chmod +x modules/your-module.sh`
3. Run the server manager: `sudo ./server-manager.sh`
4. Your module should appear in the main menu

## Debugging Tips

- Use `ui_msgbox "Debug" "Variable: $var"` to inspect values
- Check `/opt/claude/ubuntu-scripts/logs/server-manager.log` for logged messages
- Run individual functions by sourcing the libraries:
  ```bash
  source lib/ui.sh
  source lib/common.sh
  source modules/your-module.sh
  your_function
  ```
