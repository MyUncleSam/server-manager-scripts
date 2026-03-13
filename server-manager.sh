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
