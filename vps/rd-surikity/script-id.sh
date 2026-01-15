#!/bin/bash
set -e

### ============================
### RD SURIKITY
### ============================

VERSION="3.2"
NO_TELEGRAM=false
[[ "$1" == "--no-telegram" ]] && NO_TELEGRAM=true

INFO_URL="https://raw.githubusercontent.com/koderudi/tools/main/vps/rd-surikity/message/info.json"
ENV_FILE="/etc/rd-surikity.env"
LOG_FILE="/var/log/tsalert.log"
CACHE_DIR="/var/cache/rd-surikity"
CACHE_FILE="$CACHE_DIR/info.json"

if [[ $EUID -ne 0 ]]; then
  echo "❌ Run as root"
  exit 1
fi

mkdir -p "$CACHE_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log() {
  echo "$(date '+%F %T') | $1" >> "$LOG_FILE"
}

### ============================
### TELEGRAM SETUP
### ============================
if ! $NO_TELEGRAM; then
  echo "📌 Telegram Setup"
  echo "• Buat bot via @BotFather & start bot kamu"
  echo "• Ambil CHAT ID via @SukaClaimDagetBot → /cekid"
  echo
  read -s -p "BOT TOKEN : " BOT_TOKEN
  echo
  read -p "CHAT ID   : " CHAT_ID
  echo

  echo "[+] Testing Telegram..."
  RESP=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="🧪 RD Surikity test")

  if ! echo "$RESP" | grep -q '"ok":true'; then
    echo "❌ Telegram gagal"
    echo "$RESP"
    exit 1
  fi
  echo "✅ Telegram OK"
else
  BOT_TOKEN=""
  CHAT_ID=""
  echo "⚠️ Telegram disabled"
fi

### ============================
### SAVE ENV
### ============================
cat > "$ENV_FILE" <<EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
NO_TELEGRAM="$NO_TELEGRAM"
EOF
chmod 600 "$ENV_FILE"

### ============================
### TELEGRAM SENDER
### ============================
cat > /usr/local/bin/telegram-alert <<'EOF'
#!/bin/bash
source /etc/rd-surikity.env
LOG="/var/log/tsalert.log"
RATE="/tmp/rd-surikity.rate"
COOLDOWN=30

log(){ echo "$(date '+%F %T') | $1" >> "$LOG"; }

[[ "$NO_TELEGRAM" == "true" ]] && exit 0

NOW=$(date +%s)
[[ -f "$RATE" && $((NOW-$(cat $RATE))) -lt $COOLDOWN ]] && exit 0
echo "$NOW" > "$RATE"

RESP=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d text="$1" \
  -d parse_mode="HTML")

echo "$RESP" | grep -q '"ok":true' || log "TELEGRAM_FAIL | $RESP"
EOF
chmod +x /usr/local/bin/telegram-alert

### ============================
### SSH LOGIN ALERT
### ============================
cat > /usr/local/bin/ssh-login-alert <<'EOF'
#!/bin/bash
IP=$(echo $SSH_CONNECTION | awk '{print $1}')
USER=$PAM_USER
HOST=$(hostname)
echo "$(date '+%F %T') | SSH_LOGIN | user=$USER ip=$IP" >> /var/log/tsalert.log
/usr/local/bin/telegram-alert "🔐 <b>SSH LOGIN</b>\n👤 $USER\n🌍 <code>$IP</code>\n🖥 $HOST"
EOF
chmod +x /usr/local/bin/ssh-login-alert
grep -q ssh-login-alert /etc/pam.d/sshd || \
echo "session optional pam_exec.so /usr/local/bin/ssh-login-alert" >> /etc/pam.d/sshd

### ============================
### FAIL2BAN
### ============================
apt install -y fail2ban >/dev/null

cat > /usr/local/bin/fail2ban-alert <<'EOF'
#!/bin/bash
ACTION=$1
IP=$2
JAIL=$3
echo "$(date '+%F %T') | FAIL2BAN | $ACTION ip=$IP jail=$JAIL" >> /var/log/tsalert.log
/usr/local/bin/telegram-alert "🚨 <b>FAIL2BAN</b>\n⚙️ $ACTION\n🚫 <code>$IP</code>\n📦 $JAIL"
EOF
chmod +x /usr/local/bin/fail2ban-alert

cat > /etc/fail2ban/action.d/rd-surikity.conf <<EOF
[Definition]
actionban = /usr/local/bin/fail2ban-alert ban <ip> <name>
actionunban = /usr/local/bin/fail2ban-alert unban <ip> <name>
EOF

cat > /etc/fail2ban/jail.d/rd-surikity.conf <<EOF
[sshd]
enabled = true
action = rd-surikity
EOF

systemctl restart fail2ban

### ============================
### SUDO ALERT
### ============================
cat > /usr/local/bin/sudo-alert <<'EOF'
#!/bin/bash
echo "$(date '+%F %T') | SUDO | user=$USER cmd=$SUDO_COMMAND" >> /var/log/tsalert.log
/usr/local/bin/telegram-alert "⚠️ <b>SUDO</b>\n👤 $USER\n📜 <code>$SUDO_COMMAND</code>"
EOF
chmod +x /usr/local/bin/sudo-alert
grep -q sudo-alert /etc/sudoers || echo 'Defaults logfile="/var/log/sudo.log"' >> /etc/sudoers

### ============================
### INFO.JSON FETCHER
### ============================
fetch_info() {
  curl -fsSL "$INFO_URL" -o "$CACHE_FILE" || return 0
}

show_info() {
  CONTEXT="$1"
  fetch_info
  jq -r --arg ctx "$CONTEXT" '
    .messages[]
    | select(.show_on[] == $ctx)
    | "\(.type)|\(.title)|\(.body)"
  ' "$CACHE_FILE" 2>/dev/null || true
}

### ============================
### CLI TOOL
### ============================
cat > /usr/local/bin/rd-surikity <<'EOF'
#!/bin/bash
LOG="/var/log/tsalert.log"
CACHE="/var/cache/rd-surikity/info.json"

case "$1" in
  status)
    echo "🛡 RD Surikity status"
    systemctl is-active fail2ban
    echo
    [[ -f "$CACHE" ]] && jq -r '.messages[] | "• [\(.type)] \(.title)"' "$CACHE"
    ;;
  tail)
    tail -f "$LOG"
    ;;
  test)
    echo "$(date '+%F %T') | TEST | manual" >> "$LOG"
    /usr/local/bin/telegram-alert "🧪 RD Surikity test"
    ;;
  *)
    echo "Usage: rd-surikity {status|tail|test}"
    ;;
esac
EOF
chmod +x /usr/local/bin/rd-surikity

### ============================
### FINAL
### ============================
log "RD_SURIKITY_INSTALLED"
echo
echo "===================================="
echo " ✅ RD Surikity Installed"
echo "===================================="
echo "Commands:"
echo "• rd-surikity status"
echo "• rd-surikity tail"
echo "• rd-surikity test"
echo
