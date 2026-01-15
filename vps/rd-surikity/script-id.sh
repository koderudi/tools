#!/bin/bash
set -e

### ============================
### RD SURIKITY
### ============================

VERSION="3.3"
ENV_FILE="/etc/rd-surikity.env"
LOG_FILE="/var/log/tsalert.log"
CACHE_DIR="/var/cache/rd-surikity"
CACHE_FILE="$CACHE_DIR/info.json"
INFO_URL="https://raw.githubusercontent.com/koderudi/tools/main/vps/rd-surikity/message/info.json"

CHECKSUM_URL="https://raw.githubusercontent.com/koderudi/tools/main/vps/rd-surikity/security/checksum.txt"
SCRIPT_NAME="$(basename "$0")"

NO_TELEGRAM=false
UPDATE_MODE=false
NO_CHECKSUM=false

for arg in "$@"; do
  case "$arg" in
    --no-telegram) NO_TELEGRAM=true ;;
    --update) UPDATE_MODE=true ;;
    --no-checksum) NO_CHECKSUM=true ;;
  esac
done

[[ $EUID -ne 0 ]] && echo "❌ Run as root" && exit 1

### ============================
### CHECKSUM VERIFY (REMOTE)
### ============================
verify_checksum() {
  echo "🔐 Verifying checksum..."

  TMP_SUM=$(mktemp)

  if ! curl -fsSL "$CHECKSUM_URL" -o "$TMP_SUM"; then
    echo "❌ Failed to fetch checksum file"
    rm -f "$TMP_SUM"
    exit 1
  fi

  grep -q "$SCRIPT_NAME" "$TMP_SUM" || {
    echo "❌ Checksum entry not found for $SCRIPT_NAME"
    rm -f "$TMP_SUM"
    exit 1
  }

  (cd "$(dirname "$0")" && sha256sum -c "$TMP_SUM") || {
    echo "❌ Checksum verification failed"
    rm -f "$TMP_SUM"
    exit 1
  }

  rm -f "$TMP_SUM"
  echo "✅ Checksum OK"
}

if ! $NO_CHECKSUM; then
  verify_checksum
fi

### ============================
### APT HARDENING
### ============================
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export APT_LISTCHANGES_FRONTEND=none

apt_safe() {
  apt-get -o Dpkg::Use-Pty=0 \
          -o Acquire::ForceIPv4=true \
          -o APT::Get::Assume-Yes=true \
          "$@"
}

### ============================
### UNINSTALL
### ============================
if [[ "$1" == "uninstall" ]]; then
  echo "🧨 Uninstalling RD Surikity..."

  rm -f /usr/local/bin/{telegram-alert,ssh-login-alert,fail2ban-alert,sudo-alert,rd-surikity}
  rm -f /etc/fail2ban/action.d/rd-surikity.conf
  rm -f /etc/fail2ban/jail.d/rd-surikity.conf
  sed -i '/ssh-login-alert/d' /etc/pam.d/sshd

  systemctl restart fail2ban || true

  rm -f "$ENV_FILE"
  rm -rf "$CACHE_DIR"
  rm -f "$LOG_FILE"

  echo "✅ RD Surikity removed"
  exit 0
fi

### ============================
### PREP
### ============================
mkdir -p "$CACHE_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log(){ echo "$(date '+%F %T') | $1" >> "$LOG_FILE"; }

### ============================
### TELEGRAM SETUP
### ============================
BOT_TOKEN=""
CHAT_ID=""

if ! $NO_TELEGRAM; then
  [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

  if ! $UPDATE_MODE && { [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; }; then
    echo "📌 Telegram setup"
    echo "• @BotFather → create bot"
    echo "• @SukaClaimDagetBot → /cekid"
    echo
    read -s -p "BOT TOKEN : " BOT_TOKEN
    echo
    read -p "CHAT ID   : " CHAT_ID
    echo

    RESP=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
      -d chat_id="$CHAT_ID" -d text="🧪 RD Surikity test")

    echo "$RESP" | grep -q '"ok":true' || {
      echo "❌ Telegram failed"
      echo "$RESP"
      exit 1
    }
  fi
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
### INSTALL DEPENDENCY
### ============================
apt_safe update
apt_safe install fail2ban jq curl >/dev/null

### ============================
### TELEGRAM ALERT BIN
### ============================
cat > /usr/local/bin/telegram-alert <<'EOF'
#!/bin/bash
source /etc/rd-surikity.env
LOG="/var/log/tsalert.log"
RATE="/tmp/rd-surikity.rate"
COOLDOWN=30

[[ "$NO_TELEGRAM" == "true" ]] && exit 0

NOW=$(date +%s)
[[ -f "$RATE" && $((NOW-$(cat $RATE))) -lt $COOLDOWN ]] && exit 0
echo "$NOW" > "$RATE"

RESP=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" -d text="$1" -d parse_mode="HTML")

echo "$RESP" | grep -q '"ok":true' || echo "$(date) | TG_FAIL $RESP" >> "$LOG"
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
echo "$(date '+%F %T') | SSH_LOGIN user=$USER ip=$IP" >> /var/log/tsalert.log
/usr/local/bin/telegram-alert "🔐 <b>SSH LOGIN</b>\n👤 $USER\n🌍 <code>$IP</code>\n🖥 $HOST"
EOF
chmod +x /usr/local/bin/ssh-login-alert
grep -q ssh-login-alert /etc/pam.d/sshd || \
echo "session optional pam_exec.so /usr/local/bin/ssh-login-alert" >> /etc/pam.d/sshd

### ============================
### FAIL2BAN
### ============================
cat > /usr/local/bin/fail2ban-alert <<'EOF'
#!/bin/bash
echo "$(date '+%F %T') | FAIL2BAN $1 ip=$2 jail=$3" >> /var/log/tsalert.log
/usr/local/bin/telegram-alert "🚨 <b>FAIL2BAN</b>\n⚙️ $1\n🚫 <code>$2</code>\n📦 $3"
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
### CLI TOOL
### ============================
cat > /usr/local/bin/rd-surikity <<'EOF'
#!/bin/bash
case "$1" in
  status) systemctl is-active fail2ban ;;
  tail) tail -f /var/log/tsalert.log ;;
  test) /usr/local/bin/telegram-alert "🧪 RD Surikity test" ;;
  env) cat /etc/rd-surikity.env ;;
  env-edit) ${EDITOR:-nano} /etc/rd-surikity.env ;;
  *) echo "rd-surikity {status|tail|test|env|env-edit}" ;;
esac
EOF
chmod +x /usr/local/bin/rd-surikity

log "RD_SURIKITY_INSTALLED v$VERSION"
echo "✅ RD Surikity $VERSION ready"
