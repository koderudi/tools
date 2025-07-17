# 🚀 Setup Swap Script untuk VPS (Ubuntu Tested)

Script ini membantu kamu menambahkan swap memory di VPS berbasis Ubuntu secara **mudah, fleksibel, dan otomatis**, lengkap dengan pengaturan `swappiness`.

---

## 🇮🇩 Indonesia

### 📦 Cara Pakai

```bash
curl -sSL https://raw.githubusercontent.com/koderudi/tools/main/vps/swap/swap-id.sh -o setup-swap.sh && chmod +x setup-swap.sh && sudo ./setup-swap.sh
```


### 🔧 Fitur

- Deteksi otomatis apakah VPS mendukung swap
- Input ukuran swap (dalam GB)
- Penjelasan nilai swappiness sebelum memilih
- Bisa tekan enter untuk pakai default swappiness = `30`
- Auto persist setelah reboot (dimasukkan ke `/etc/fstab`)
- Kompatibel dengan Ubuntu 18.04, 20.04, 22.04

---



## 🇺🇸 English

### 📦 How to Use

```bash
curl -sSL https://raw.githubusercontent.com/koderudi/tools/main/vps/swap/swap-en.sh -o setup-swap.sh && chmod +x setup-swap.sh && sudo ./setup-swap.sh
```


### 🔧 Features

- Automatically detects if VPS supports swap
- Ask for desired swap size (in GB)
- Explains swappiness levels before input
- Press enter to use default swappiness = `30`
- Persistent after reboot (via `/etc/fstab`)
- Compatible with Ubuntu 18.04, 20.04, 22.04

---

## ⚠️ Notes

- VPS berbasis **OpenVZ (LXC/Container)** tidak mendukung swap.
- Rekomendasi gunakan VPS **KVM-based**.
