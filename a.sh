#!/bin/bash
# Android-x86 9.0 live session bằng Proot + QEMU + noVNC + GPU ảo
# Mount /dev /proc /sys /tmp, chạy trực tiếp trong rootfs

set -e

# -----------------------------
# Cấu hình
# -----------------------------
ALPINE_ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.2-x86_64.tar.gz"
INSTALL_DIR="./android_vm"
ANDROID_ISO_URL="https://downloads.sourceforge.net/project/android-x86/Release%209.0/android-x86_64-9.0-r2.iso"
ANDROID_ISO="$INSTALL_DIR/android-x86_64-9.0-r2.iso"
VNC_PORT=5900
WEB_PORT=6080
MEMORY=2048
CPUS=$(nproc)

# -----------------------------
# Hàm hỗ trợ
# -----------------------------
dstat() { echo -e "\033[1;37m==> \033[1;34m$@\033[0m"; }
die() { echo -e "\033[41mFATAL ERROR. Exit.\033[0m"; exit 1; }

# -----------------------------
# Tải rootfs Alpine
# -----------------------------
bootstrap_rootfs() {
  dstat "Tạo thư mục rootfs..."
  mkdir -p "$INSTALL_DIR"
  cd "$INSTALL_DIR"
  
  dstat "Tải Alpine rootfs..."
  wget -c "$ALPINE_ROOTFS_URL" -O alpine.tar.gz || die
  tar -xzf alpine.tar.gz || die
  rm alpine.tar.gz
  cd ..
}

# -----------------------------
# Chạy lệnh trong Proot
# -----------------------------
run_container() {
  proot -r "$INSTALL_DIR" -b /dev -b /proc -b /sys -b /tmp -b /bin -b /usr/bin /bin/sh -c "$1"
}

# -----------------------------
# Cài package cần thiết
# -----------------------------
install_packages() {
  dstat "Cập nhật APK và cài package..."
  run_container "apk update && apk add --no-cache bash wget git qemu qemu-system-x86_64 python3 py3-pip openssl unzip mesa-dri-gallium xvfb websockify"
  
  dstat "Cài websockify bằng pip..."
  run_container "pip install --break-system-packages websockify"
}

# -----------------------------
# Clone noVNC + tạo chứng chỉ SSL
# -----------------------------
install_noVNC() {
  dstat "Clone noVNC..."
  run_container "git clone https://github.com/h3l2f/noVNC1 /home/container/noVNC1"
  
  dstat "Tạo chứng chỉ SSL cho noVNC..."
  run_container "
    cd /home/container/noVNC1 && \
    openssl req -x509 -sha256 -days 365 -nodes -newkey rsa:2048 \
      -subj '/CN=localhost/C=US/L=Local' -keyout self.key -out self.crt && \
    cp vnc.html index.html
  "
}

# -----------------------------
# Tải Android-x86 ISO
# -----------------------------
download_android_iso() {
  dstat "Tải Android-x86 ISO..."
  run_container "wget -c $ANDROID_ISO_URL -O $ANDROID_ISO"
}

# -----------------------------
# Chạy noVNC + Android-x86 live ISO
# -----------------------------
start_vnc_and_vm() {
  dstat "Khởi chạy noVNC server (web)..."
  run_container "cd /home/container/noVNC1 && ./utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $WEB_PORT &"
  echo "✔ Web noVNC: http://<HOST-IP>:$WEB_PORT"
  echo "✔ RealVNC client: connect to <HOST-IP>:$VNC_PORT"

  dstat "Khởi chạy Android-x86 live ISO với GPU ảo..."
  run_container "
    qemu-system-x86_64 -m $MEMORY -smp $CPUS \
      -boot d -cdrom $ANDROID_ISO \
      -vga virtio -display sdl,gl=on \
      -usbdevice tablet \
      -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
      -display vnc=127.0.0.1:$((VNC_PORT-5900))
  "
}

# -----------------------------
# Main
# -----------------------------
bootstrap_rootfs
install_packages
install_noVNC
download_android_iso
start_vnc_and_vm
