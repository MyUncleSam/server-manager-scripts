#!/bin/bash
#
# Ubuntu Server Manager - Entry Point with Auto-Update
# Checks for updates via git pull before launching the server manager.
#
# To disable auto-updates, create a file named DISABLE_AUTO_UPDATE
# in the same directory as this script:
#   touch /path/to/server-manager/DISABLE_AUTO_UPDATE
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
CORE_SCRIPT="${SCRIPT_DIR}/server-manager-core.sh"
DISABLE_FILE="${SCRIPT_DIR}/DISABLE_AUTO_UPDATE"

# Toggle auto-update on/off
switch_auto_update() {
    if [[ -f "$DISABLE_FILE" ]]; then
        rm -f "$DISABLE_FILE"
        echo "Auto-update has been enabled."
    else
        touch "$DISABLE_FILE"
        echo "Auto-update has been disabled."
    fi
    exit 0
}

# Update only (do not launch the manager)
update_only() {
    if ! command -v git &>/dev/null; then
        echo "Error: git is not installed."
        exit 1
    fi

    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        echo "Error: not a git repository."
        exit 1
    fi

    echo "Updating server manager..."
    if git -C "$SCRIPT_DIR" pull --ff-only; then
        echo "Update complete."
    else
        echo "Update failed."
        exit 1
    fi
    exit 0
}

# Show help
show_help() {
    echo "Ubuntu Server Manager"
    echo ""
    echo "Usage: server-manager [OPTION]"
    echo ""
    echo "Options:"
    echo "  --help                 Show this help message"
    echo "  --update               Update to the latest version without launching"
    echo "  --switch-auto-update   Toggle auto-update on startup on/off"
    echo ""
    echo "Without options, the server manager launches normally"
    echo "(with auto-update check if enabled)."
    exit 0
}

# Handle command-line arguments
case "${1:-}" in
    --help|-h)
        show_help
        ;;
    --switch-auto-update)
        switch_auto_update
        ;;
    --update)
        update_only
        ;;
esac

# Auto-update check
auto_update() {
    # Check if git is installed
    if ! command -v git &>/dev/null; then
        return 0
    fi

    # Check if we are inside a git repository
    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        return 0
    fi

    # Check if the branch is master or main
    local branch
    branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
    if [[ "$branch" != "master" && "$branch" != "main" ]]; then
        return 0
    fi

    # Check if auto-update is disabled
    if [[ -f "${SCRIPT_DIR}/DISABLE_AUTO_UPDATE" ]]; then
        return 0
    fi

    # Record checksum of this script before pulling
    local checksum_before
    checksum_before=$(md5sum "${BASH_SOURCE[0]}" 2>/dev/null | cut -d' ' -f1) || return 0

    # Attempt git pull (do not fail if network is unavailable)
    echo "Checking for updates..."
    if git -C "$SCRIPT_DIR" pull --ff-only 2>/dev/null; then
        # Check if the entry script itself was updated
        local checksum_after
        checksum_after=$(md5sum "${BASH_SOURCE[0]}" 2>/dev/null | cut -d' ' -f1)

        if [[ "$checksum_before" != "$checksum_after" ]]; then
            echo ""
            echo "The updater script itself has been updated."
            echo "Please restart the server manager to use the new version:"
            echo "  sudo $0"
            exit 0
        fi
    else
        echo "Could not check for updates (network unavailable?). Continuing..."
    fi
}

auto_update

# Launch the server manager
exec "$CORE_SCRIPT" "$@"
