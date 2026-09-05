# Ubuntu Server Manager

A modular, dialog-based TUI (Text User Interface) tool for managing Ubuntu servers. Built with whiptail for compatibility with remote SSH sessions.

## Features

- **Auto-update** - Automatically pulls latest changes on startup (when installed via git)
- Modular architecture - easily extensible
- Dialog-based interface using whiptail
- Works over SSH (non-interactive sessions)
- Comprehensive server management capabilities
- **Skippable dependency check** - Run on non-Debian distributions (Arch, Fedora, ...)

See [FEATURES.md](FEATURES.md) for a complete list of modules and features.

## Requirements

- Ubuntu Server (18.04+)
- Root/sudo access
- whiptail (usually pre-installed)

### Other distributions

The tool targets Ubuntu/Debian, and the startup dependency check reports missing
packages using `apt-get`. On distributions without APT (Arch, Fedora, openSUSE,
Alpine, ...) the check can be bypassed — see
[Dependency Check](#dependency-check) below.

Note that modules which install or remove packages still use `apt-get`/`dpkg`
and will not work on non-APT systems. Modules that only read system state or
manage systemd services work regardless of the package manager.

## Installation

### Quick Install (recommended)

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/MyUncleSam/server-manager-scripts/master/install.sh | sudo bash
```

This installs dependencies, clones the repo to `/opt/server-manager`, and registers the `server-manager` command globally. Re-running the command will update an existing installation.

### Manual Install

```bash
git clone https://github.com/MyUncleSam/server-manager-scripts.git /opt/server-manager
chmod +x /opt/server-manager/server-manager.sh
sudo /opt/server-manager/server-manager.sh
```

## Usage

Run the server manager with root privileges:

```bash
sudo server-manager
```

### Auto-Update

The server manager automatically checks for updates via `git pull` on startup. This only happens when:
- Git is installed
- The repository is on the `master` or `main` branch
- Network is available (skips gracefully if not)

To toggle auto-updates on or off:

```bash
sudo server-manager --switch-auto-update
```

This switches the current state — if auto-update is enabled it will be disabled, and vice versa. The current state is printed after each toggle.

To manually update without launching the manager:

```bash
sudo server-manager --update
```

### Dependency Check

On startup the manager verifies that `whiptail` is available. When it is
missing, the install hint is adapted to the detected package manager
(`apt-get`, `pacman`, `dnf`, `zypper` or `apk`).

To skip the check for a single run:

```bash
sudo server-manager --skip-dependency-check
```

To disable it permanently:

```bash
sudo server-manager --switch-dependency-check
```

This switches the current state — if the check is enabled it will be disabled,
and vice versa. The current state is printed after each toggle. The setting is
stored in the `DISABLE_DEPENDENCY_CHECK` file next to the scripts.

The environment variable `SERVER_MANAGER_SKIP_DEPS=1` has the same effect as
`--skip-dependency-check`, which is handy for wrappers and aliases:

```bash
SERVER_MANAGER_SKIP_DEPS=1 sudo -E server-manager
```

### Navigation

Navigate using:
- Arrow keys to move
- Enter to select
- Tab to switch between buttons
- Space to toggle checkboxes
- Esc or Cancel/Exit to go back

## Project Structure

```
ubuntu-scripts/
├── server-manager.sh      # Entry point (auto-update + launch)
├── server-manager-core.sh # Main server manager
├── lib/
│   ├── ui.sh              # Dialog-based UI helper functions
│   └── common.sh          # Common utility functions
├── modules/               # Feature modules
│   ├── apt.sh
│   ├── cron.sh
│   ├── custom-scripts.sh
│   ├── docker.sh
│   ├── fail2ban.sh
│   ├── hostname.sh
│   ├── motd.sh
│   ├── network.sh
│   ├── ntp-client.sh
│   ├── podman.sh
│   ├── software.sh
│   ├── ssh.sh
│   ├── system-info.sh
│   ├── ufw.sh
│   ├── ufw-docker.sh
│   ├── unattended-upgrades.sh
│   ├── update-alternatives.sh
│   ├── user.sh
│   └── vm-guest.sh
├── modules-files/         # Module data files
│   ├── cron/              # Pre-configured cron jobs
│   ├── custom-scripts/    # Custom utility scripts
│   ├── docker/            # Docker compose templates
│   └── podman/            # Podman compose + quadlet templates
├── logs/                  # Log files (gitignored)
├── CLAUDE.md              # AI assistant instructions
├── FEATURES.md            # Detailed feature list
└── README.md              # This file
```

## Creating Custom Modules

See [CLAUDE.md](CLAUDE.md) for detailed instructions on creating new modules.

Basic template:

```bash
#!/bin/bash

module_info() {
    echo "Module Name|Short description"
}

module_main() {
    while true; do
        local choice
        choice=$(ui_menu "Title" "Select:" \
            "action1" "Description") || break

        case "$choice" in
            action1) do_something ;;
        esac
    done
}
```

## Security

This project follows security best practices:

- No use of `eval` for command construction - all commands use direct execution or arrays
- Temporary files created with `mktemp` (unpredictable paths, no symlink attacks)
- Remote installation scripts are downloaded to temp files before execution (no `curl | bash`)
- User input is escaped before use in `sed` replacement patterns
- IP address validation includes octet range checking (0-255)
- Log files are created with restricted permissions (600)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Acknowledgments

- Built with [whiptail](https://en.wikibooks.org/wiki/Bash_Shell_Scripting/Whiptail)
- Inspired by various server management tools
