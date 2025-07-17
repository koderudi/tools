#!/bin/bash

# ========== Setup Swap Script ==========
# Author  : Rudi
# Purpose : Flexible swap setup for Ubuntu VPS
# =======================================

echo "🔍 Checking swap support on this VPS..."
if grep -qa 'openvz' /proc/1/environ || hostnamectl | grep -qi openvz || systemd-detect-virt | grep -qi openvz; then
  echo "❌ This VPS is based on OpenVZ (container). Swap is NOT supported."
  echo "ℹ️  Use a KVM-based VPS if you want to enable swap."
  exit 1
fi

# 🔐 Check for root access
if [[ "$EUID" -ne 0 ]]; then
  echo "❌ This script must be run as root. Use: sudo ./swap-en.sh"
  exit 1
fi

# 🔢 Ask for swap size
read -p "Enter desired swap size (in GB): " SWAP_GB
if ! [[ "$SWAP_GB" =~ ^[0-9]+$ ]]; then
  echo "❌ Invalid input. Please enter a number (e.g. 2, 4, 8)"
  exit 1
fi
SWAP_MB=$((SWAP_GB * 1024))

# 📘 Swappiness explanation
echo ""
echo "ℹ️  Swappiness value explanation:"
echo "  0   : ⚡ Maximize RAM usage, only use swap when absolutely necessary (Super responsive)"
echo "  1-30: ✅ Recommended. Swap is used only when RAM is nearly full (Balanced)"
echo " 31-60: 🟡 Swap is used earlier. Good for idle or lightweight VPS"
echo " 61-100: 🔵 Swap is used aggressively. Useful for small RAM systems"
echo ""

# 💡 Ask for swappiness (optional, default: 30)
read -p "Enter swappiness value (0-100) [default: 30]: " SWAPPINESS
if [[ -z "$SWAPPINESS" ]]; then
  SWAPPINESS=30
  echo "ℹ️  Using default swappiness value: $SWAPPINESS"
elif ! [[ "$SWAPPINESS" =~ ^[0-9]+$ ]] || [ "$SWAPPINESS" -lt 0 ] || [ "$SWAPPINESS" -gt 100 ]; then
  echo "❌ Swappiness must be a number between 0 and 100."
  exit 1
fi

# 🧹 Clean existing swap if any
swapoff -a 2>/dev/null
rm -f /swapfile

# 🧱 Create new swapfile
echo ""
echo "📦 Creating swap file of ${SWAP_GB} GB (${SWAP_MB} MB)..."
if command -v fallocate &> /dev/null; then
  fallocate -l ${SWAP_GB}G /swapfile
else
  dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_MB status=progress
fi

chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile || { echo "❌ Failed to activate swap. Your VPS may not support it."; exit 1; }

# 📝 Add to fstab for persistence
if ! grep -qF '/swapfile none swap sw 0 0' /etc/fstab; then
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ⚙️ Set swappiness
echo "vm.swappiness=$SWAPPINESS" | tee /etc/sysctl.d/99-swappiness.conf >/dev/null
sysctl -w vm.swappiness=$SWAPPINESS >/dev/null

# ✅ Show result
echo ""
echo "✅ Swap of ${SWAP_GB} GB is now active with swappiness $SWAPPINESS!"
echo ""
free -h
echo ""
echo "🎯 Current swappiness value: $(cat /proc/sys/vm/swappiness)"
