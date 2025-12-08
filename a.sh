#!/bin/bash
# Android-x86 9.0-r2 LIVE ISO ONLY (không tạo ổ cứng)
# Treo Roblox 24/7 – chỉ 15 giây khởi động
# Copy paste nguyên file này vào Termux rồi chạy thôi

set -e

# ============================= CẤU HÌNH =============================
SERVER_PORT="${SERVER_PORT:-6080}"     # Port noVNC
MEMORY="4096"                          # 3072–6144 tùy máy
CPUS="$(nproc --all)"
ISO_URL="https://sourceforge.net/projects/android-x86/files/Release%209.0/android-x86_64-9.0-r2.iso/download"
ISO_NAME="android-x86_64-9.0-r2.iso"
WORK_DIR="$HOME/android-live-roblox"

# ==================================================================
dstat() { echo -e "\033[1;36m[+] $*\033[0m"; }
die()   { echo -e "\033[1;31m[-] $*\033[0m"; exit 1>&2; exit 1; }

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Tải PROOT siêu nhanh (chỉ 1.2MB)
[ -f proot ] || {
  dstat "Tải PROOT mới nhất..."
  curl -L "https://github.com/proot-me/proot-static/releases/download/v5.3.0/proot-v5.3.0-x86_64-static" -o proot
  chmod +x proot
}

# Tải Alpine rootfs siêu nhẹ (chỉ lần đầu)
[ -d rootfs/bin ] || {
  dstat "Tải Alpine rootfs (40MB)..."
  curl -L "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.2-x86_64.tar.gz" | tar -xz
  mv rootfs rootfs_tmp && mkdir rootfs && mv rootfs_tmp/* rootfs/ && rmdir rootfs_tmp
}

# Tải Android-x86 ISO (chỉ lần đầu ~800MB)
[ -f "$ISO_NAME" ] || {
  dstat "Tải Android-x86 9.0-r2 ISO (~800MB)... ngồi chờ chút nha"
  curl -L "$ISO_URL" -o "$ISO_NAME"
}

# Cài gói cần thiết trong Alpine (chỉ lần đầu, ~5 phút)
if [ ! -f rootfs/.setup_done ]; then
  dstat "Cài QEMU + noVNC trong Alpine..."
  ./proot -0 -r rootfs -b /dev -b /proc -b /sys -b /tmp -b /sdcard:/sdcard \
    /bin/sh -c "
    apk update
    apk add --no-cache qemu-system-x86_64 qemu-ui-opengl mesa-dri-gallium mesa-va-gallium websockify git openssl
    git clone https://github.com/novnc/noVNC /opt/noVNC 2>/dev/null || true
    cd /opt/noVNC
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout self.key -out self.crt -subj '/CN=localhost' 2>/dev/null
    cp vnc.html index.html
    touch /.setup_done
  "
  cp rootfs/.setup_done rootfs/.setup_done 2>/dev/null || touch rootfs/.setup_done
fi

# ============================= KHỞI ĐỘNG =============================
dstat "Dọn dẹp tiến trình cũ..."
killall novnc_proxy qemu-system-x86_64 2>/dev/null || true
sleep 2

dstat "Khởi động noVNC – port $SERVER_PORT"
./proot -0 -r rootfs -b /dev -b /proc -b /sys -b /tmp -b /dev/dri \
  -w /opt/noVNC /bin/sh -c "./utils/novnc_proxy --vnc localhost:5901 --listen 0.0.0.0:$SERVER_PORT --cert self.crt --key self.key" &
sleep 4

dstat "KHỞI ĐỘNG ANDROID-X86 LIVE (chỉ 10–15 giây là vào được Desktop!)"
./proot -0 -r rootfs \
  -b /dev -b /proc -b /sys -b /tmp -b /dev/dri \
  -b "$WORK_DIR/$ISO_NAME:/iso/$ISO_NAME" \
  -w /root /bin/sh -c "
    qemu-system-x86_64 \\
      -m $MEMORY -smp $CPUS -cpu max \\
      -machine q35 \\
      -boot d -cdrom /iso/$ISO_NAME \\
      -device virtio-gpu-pci,virgl=on \\
      -display gtk,gl=on,show-cursor=on \\
      -vnc :1 \\
      -usb -device usb-tablet \\
      -netdev user,id=net0,hostfwd=tcp::5555-:5555,hostfwd=tcp::8080-:8000 \\
      -device virtio-net-pci,netdev=net0 \\
      -rtc base=utc,clock=host \\
      -soundhw ac97 \\
      -device virtio-rng-pci
  "

dstat "Đã tắt bất ngờ? Không sao, chạy lại script là vào ngay!"
