#!/bin/bash
# =============================================================================
# RealVNC Headless Virtual Desktop Setup Script
# For Raspberry Pi OS Lite (Debian 12 Bookworm)
# =============================================================================

set -e  # Exit on any error

# =============================================================================
# Color output helpers
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# =============================================================================
# Banner
# =============================================================================
echo -e "${BLUE}"
echo "=============================================="
echo "  RealVNC Headless Setup for Raspberry Pi"
echo "  Raspberry Pi OS Lite (Debian 12 Bookworm)"
echo "=============================================="
echo -e "${NC}"

# =============================================================================
# Check running as non-root (we use sudo internally)
# =============================================================================
if [ "$EUID" -eq 0 ]; then
    error "Please run this script as a normal user, not root. Use: bash setup-vnc.sh"
fi

# =============================================================================
# Gather User Input
# =============================================================================
echo ""
info "Gathering configuration..."
echo ""

# Username
DEFAULT_USER=$(whoami)
read -p "VNC session username [${DEFAULT_USER}]: " INPUT_USER
VNC_USER="${INPUT_USER:-$DEFAULT_USER}"

# Confirm user exists
if ! id "$VNC_USER" &>/dev/null; then
    error "User '$VNC_USER' does not exist on this system."
fi

# Hostname
DEFAULT_HOST=$(hostname)
read -p "Hostname [${DEFAULT_HOST}]: " INPUT_HOST
VNC_HOST="${INPUT_HOST:-$DEFAULT_HOST}"

# Resolution
read -p "VNC resolution [1920x1080]: " INPUT_RES
VNC_RESOLUTION="${INPUT_RES:-1920x1080}"

# Port
read -p "VNC port [5901]: " INPUT_PORT
VNC_PORT="${INPUT_PORT:-5901}"

# Display number derived from port (5901 = :1, 5902 = :2 etc)
DISPLAY_NUM=$((VNC_PORT - 5900))

# Home directory
VNC_HOME=$(eval echo "~$VNC_USER")

# PID file path
VNC_PID_FILE="${VNC_HOME}/.vnc/${VNC_HOST}:${DISPLAY_NUM}.pid"

# =============================================================================
# Confirm Settings
# =============================================================================
echo ""
echo -e "${YELLOW}Configuration Summary:${NC}"
echo "  Username:    $VNC_USER"
echo "  Home:        $VNC_HOME"
echo "  Hostname:    $VNC_HOST"
echo "  Resolution:  $VNC_RESOLUTION"
echo "  VNC Port:    $VNC_PORT"
echo "  Display:     :$DISPLAY_NUM"
echo "  PID file:    $VNC_PID_FILE"
echo ""
read -p "Proceed with these settings? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    info "Aborted by user."
    exit 0
fi

# =============================================================================
# Step 1 — Update System
# =============================================================================
echo ""
info "Step 1 — Updating system packages..."
sudo apt update -y && sudo apt upgrade -y
success "System updated."

# =============================================================================
# Step 2 — Install Required Packages
# =============================================================================
echo ""
info "Step 2 — Installing required packages..."
sudo apt install -y \
    realvnc-vnc-server \
    openbox \
    xterm
success "Packages installed."

# =============================================================================
# Step 3 — Disable and Mask Unwanted VNC Services
# =============================================================================
echo ""
info "Step 3 — Disabling unwanted VNC services..."

# Disable Service Mode
if systemctl is-active --quiet vncserver-x11-serviced.service; then
    sudo systemctl stop vncserver-x11-serviced.service
fi
sudo systemctl disable vncserver-x11-serviced.service 2>/dev/null || true
success "Service Mode disabled."

# Mask Virtual daemon
if systemctl is-active --quiet vncserver-virtuald.service; then
    sudo systemctl stop vncserver-virtuald.service
fi
sudo systemctl disable vncserver-virtuald.service 2>/dev/null || true
sudo systemctl mask vncserver-virtuald.service
success "Virtual daemon masked."

# =============================================================================
# Step 4 — Set VNC Password
# =============================================================================
echo ""
info "Step 4 — Setting VNC password..."
echo ""
warning "You will be prompted to set a VNC password."
warning "Minimum 6 characters required."
echo ""

# Run as the VNC user
if [ "$VNC_USER" != "$(whoami)" ]; then
    sudo -u "$VNC_USER" vncpasswd -virtual
else
    vncpasswd -virtual
fi
success "VNC password set."

# =============================================================================
# Step 5 — Create Custom xstartup
# =============================================================================
echo ""
info "Step 5 — Creating custom xstartup..."

sudo tee /etc/vnc/xstartup.custom > /dev/null << 'EOF'
#!/bin/bash

# Keyboard layout
[ -x /usr/bin/setxkbmap ] && setxkbmap us

# Grey background
xsetroot -solid grey

# Start minimal window manager
exec openbox-session
EOF

sudo chmod +x /etc/vnc/xstartup.custom
success "Custom xstartup created at /etc/vnc/xstartup.custom"

# =============================================================================
# Step 6 — Create systemd Service
# =============================================================================
echo ""
info "Step 6 — Creating systemd template service..."

sudo tee /etc/systemd/system/vncserver-virtual-session@.service > /dev/null << EOF
[Unit]
Description=RealVNC Virtual Desktop Session for %i
After=network.target

[Service]
Type=forking
User=%i
Group=%i
WorkingDirectory=/home/%i

ExecStartPre=/bin/sh -c 'kill \$(cat /home/%i/.vnc/%H:${DISPLAY_NUM}.pid) 2>/dev/null; rm -f /tmp/.X${DISPLAY_NUM}-lock /tmp/.X11-unix/X${DISPLAY_NUM} /home/%i/.vnc/%H:${DISPLAY_NUM}.pid; sleep 1; exit 0'
ExecStart=/usr/bin/vncserver-virtual :${DISPLAY_NUM} -geometry ${VNC_RESOLUTION} -depth 24 -rfbport ${VNC_PORT}
ExecStop=/bin/sh -c 'kill \$(cat /home/%i/.vnc/%H:${DISPLAY_NUM}.pid) 2>/dev/null; rm -f /tmp/.X${DISPLAY_NUM}-lock /tmp/.X11-unix/X${DISPLAY_NUM} /home/%i/.vnc/%H:${DISPLAY_NUM}.pid; exit 0'

Restart=on-failure
RestartSec=5
StartLimitInterval=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

success "Systemd template service created."

# =============================================================================
# Step 7 — Enable and Start Service
# =============================================================================
echo ""
info "Step 7 — Enabling and starting VNC service for user: ${VNC_USER}..."

sudo systemctl daemon-reload
sudo systemctl enable vncserver-virtual-session@${VNC_USER}.service
sudo systemctl start vncserver-virtual-session@${VNC_USER}.service

sleep 3

# =============================================================================
# Step 8 — Verify
# =============================================================================
echo ""
info "Step 8 — Verifying setup..."

# Check service status
if systemctl is-active --quiet vncserver-virtual-session@{VNC_USER}.service; then
    success "VNC service is running."
else
    error "VNC service failed to start. Check: journalctl -u vncserver-virtual-session@{VNC_USER}.service"
fi

# Check port is listening
if ss -tlnp | grep -q ":${VNC_PORT}"; then
    success "Port ${VNC_PORT} is listening."
else
    warning "Port ${VNC_PORT} is not yet listening. Service may still be starting."
    warning "Check with: ss -tlnp | grep ${VNC_PORT}"
fi

# =============================================================================
# Done
# =============================================================================
PI_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}"
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo -e "${NC}"
echo "  Connect via RealVNC Viewer to:"
echo ""
echo -e "  ${YELLOW}${PI_IP}:${VNC_PORT}${NC}"
echo ""
echo "  Service management:"
echo "  sudo systemctl status  vncserver-virtual-session@{VNC_USER}.service"
echo "  sudo systemctl restart vncserver-virtual-session@{VNC_USER}.service"
echo "  sudo systemctl stop    vncserver-virtual-session@{VNC_USER}.service"
echo ""
echo "  View logs:"
echo "  journalctl -u vncserver-virtual-session@{VNC_USER}.service -f"
echo ""
echo "  VNC session log:"
echo "  cat ${VNC_HOME}/.vnc/${VNC_HOST}:${DISPLAY_NUM}.log"
echo ""
