#!/bin/bash
#
# Ubuntu Server Manager - One-line Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/MyUncleSam/server-manager-scripts/master/install.sh | sudo bash
#
# What this script does:
#   1. Installs required packages (git, whiptail)
#   2. Clones the repository to /opt/server-manager
#   3. Registers the "server-manager" command for root
#

set -e

INSTALL_DIR="/opt/server-manager"
REPO_URL="https://github.com/MyUncleSam/server-manager-scripts.git"
COMMAND_PATH="/usr/local/sbin/server-manager"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    error "This installer must be run as root (use sudo)."
    exit 1
fi

# Check OS
if [[ ! -f /etc/os-release ]] || ! grep -qi 'ubuntu\|debian' /etc/os-release; then
    warn "This tool is designed for Ubuntu/Debian. Proceeding anyway..."
fi

# Install dependencies
info "Installing dependencies..."
apt-get update -qq
apt-get install -y -qq git whiptail > /dev/null

# Clone or update repository
if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Existing installation found. Updating..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    if [[ -d "$INSTALL_DIR" ]]; then
        warn "$INSTALL_DIR exists but is not a git repo. Removing..."
        rm -rf "$INSTALL_DIR"
    fi
    info "Cloning repository to $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# Ensure scripts are executable
chmod +x "$INSTALL_DIR/server-manager.sh"
chmod +x "$INSTALL_DIR/server-manager-core.sh"

# Register command
info "Registering 'server-manager' command..."
cat > "$COMMAND_PATH" << 'WRAPPER'
#!/bin/bash
exec /opt/server-manager/server-manager.sh "$@"
WRAPPER
chmod +x "$COMMAND_PATH"

echo ""
info "Installation complete!"
echo ""
echo "  Run the server manager with:"
echo "    sudo server-manager"
echo ""
