#!/bin/bash

# ========== Setup Swap Script ==========
# Author  : Rudi
# Purpose : Fleksibel setup swap di VPS (Ubuntu Tested)
# =======================================

echo "🔍 Mengecek dukungan swap pada VPS..."
if grep -qa 'openvz' /proc/1/environ || hostnamectl | grep -qi openvz || systemd-detect-virt | grep -qi openvz; then
  echo "❌ VPS ini berbasis OpenVZ (container). Swap TIDAK didukung."
  echo "ℹ️  Gunakan VPS berbasis KVM jika ingin menggunakan swap."
  exit 1
fi

# 🔐 Cek akses root
if [[ "$EUID" -ne 0 ]]; then
  echo "❌ Harus dijalankan sebagai root. Gunakan: sudo ./swap-id.sh"
  exit 1
fi

# 🔢 Input ukuran swap
read -p "Masukkan ukuran swap yang diinginkan (dalam GB): " SWAP_GB
if ! [[ "$SWAP_GB" =~ ^[0-9]+$ ]]; then
  echo "❌ Input tidak valid. Masukkan angka (contoh: 2, 4, 8)"
  exit 1
fi
SWAP_MB=$((SWAP_GB * 1024))

# 📘 Penjelasan Swappiness
echo ""
echo "ℹ️  Penjelasan tentang nilai swappiness:"
echo "  0   : ⚡ Maksimalkan RAM, swap hanya saat darurat (Super responsif)"
echo "  1-30: ✅ Direkomendasikan. Swap hanya saat RAM hampir habis (Seimbang)"
echo " 31-60: 🟡 Swap lebih cepat aktif. Cocok untuk VPS idle atau ringan"
echo " 61-100: 🔵 Swap sangat aktif. Cocok untuk sistem dengan RAM kecil"
echo ""

# 💡 Input swappiness (boleh kosong → default 30)
read -p "Masukkan nilai swappiness (0-100) [default: 30]: " SWAPPINESS
if [[ -z "$SWAPPINESS" ]]; then
  SWAPPINESS=30
  echo "ℹ️  Menggunakan nilai default swappiness: $SWAPPINESS"
elif ! [[ "$SWAPPINESS" =~ ^[0-9]+$ ]] || [ "$SWAPPINESS" -lt 0 ] || [ "$SWAPPINESS" -gt 100 ]; then
  echo "❌ Swappiness harus antara 0–100."
  exit 1
fi

# 🧹 Bersih-bersih swap lama
swapoff -a 2>/dev/null
rm -f /swapfile

# 🧱 Buat file swap
echo ""
echo "📦 Membuat swap sebesar ${SWAP_GB} GB (${SWAP_MB} MB)..."
if command -v fallocate &> /dev/null; then
  fallocate -l ${SWAP_GB}G /swapfile
else
  dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_MB status=progress
fi

chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile || { echo "❌ Gagal mengaktifkan swap. VPS Anda mungkin tidak mendukung."; exit 1; }

# 📝 Tambahkan ke fstab
if ! grep -qF '/swapfile none swap sw 0 0' /etc/fstab; then
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ⚙️ Atur swappiness
echo "vm.swappiness=$SWAPPINESS" | tee /etc/sysctl.d/99-swappiness.conf >/dev/null
sysctl -w vm.swappiness=$SWAPPINESS >/dev/null

# ✅ Tampilkan hasil
echo ""
echo "✅ Swap ${SWAP_GB} GB aktif dengan swappiness $SWAPPINESS!"
echo ""
free -h
echo ""
echo "🎯 Nilai swappiness saat ini: $(cat /proc/sys/vm/swappiness)"
