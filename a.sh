#!/bin/bash
# Android-x86 9.0 live session với Proot/dockerd + GPU ảo + noVNC + VNC
# Debug log + fix lỗi phổ biến

set -e

# -----------------------------
# Cấu hình
# -----------------------------
ALPINE_ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.2-x86_64.tar.gz"
INSTALL_DIR="./android_vm"
ANDROID_ISO_URL="https://downloads.sourceforge.net/project/android-x86/Release%209.0/android-x86_64-9.0-r2.iso"
ANDROID_ISO="$INSTALL_DIR/android-x86_64-9.0-r2.iso"
VNC_PORT=5901
WEB_PORT=6080
MEMORY=2048
CPUS=$(nproc)
HOSTFWD_PORT=25275
PROOT_URL="https://proot.gitlab.io/proot/bin/proot"

# -----------------------------
# Hàm hỗ trợ
# -----------------------------
dstat() { echo -e "\033[1;37m==> \033[1;34m$@\033[0m"; }
logerr() { echo -e "\033[41mERROR: $@\033[0m"; }
die() { logerr "$@"; exit 1; }

# -----------------------------
# Kiểm tra command tồn tại
# -----------------------------
check_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Command '$1' not found. Install it first."
}

# -----------------------------
# Tải dockerd (Proot)
# -----------------------------
bootstrap_proot() {
  dstat "Kiểm tra dockerd (Proot)..."
  if [ ! -f dockerd ]; then
    dstat "Tải dockerd từ $PROOT_URL..."
    wget -O dockerd "$PROOT_URL" || die "Không tải được dockerd"
    chmod +x dockerd
  else
    dstat "dockerd đã tồn tại, bỏ qua."
  fi
}

# -----------------------------
# Bootstrap rootfs Alpine
# -----------------------------
bootstrap_rootfs() {
  dstat "Tạo thư mục rootfs..."
  mkdir -p "$INSTALL_DIR"
  cd "$INSTALL_DIR"
  
  dstat "Tải Alpine rootfs..."
  wget -c "$ALPINE_ROOTFS_URL" -O alpine.tar.gz || die "Không tải được Alpine rootfs"
  tar -xzf alpine.tar.gz || die "Giải nén rootfs lỗi"
  rm alpine.tar.gz
  
  mkdir -p home/container shared/android
  cd ..
}

# -----------------------------
# Chạy lệnh trong dockerd/Proot
# -----------------------------
run_container() {
  ./dockerd -r "$INSTALL_DIR" \
    -b /dev -b /proc -b /sys -b /tmp -b /bin -b /usr/bin \
    -b "$INSTALL_DIR":"$INSTALL_DIR" \
    /bin/sh -c "$1"
}

# -----------------------------
# Cài package cần thiết + debug
# -----------------------------
install_packages() {
  dstat "Cập nhật APK và cài package..."
  run_container "
    echo '==> Cập nhật APK...';
    apk update || echo 'WARNING: apk update thất bại';
    echo '==> Cài package cần thiết...';
    apk add --no-cache bash wget git qemu qemu-system-x86_64 python3 py3-pip openssl unzip mesa-dri-gallium xvfb websockify || echo 'WARNING: apk add thất bại'
  "
  dstat "Cài websockify..."
  run_container "pip install --break-system-packages websockify || echo 'WARNING: pip install websockify thất bại'"
}

# -----------------------------
# Clone noVNC + tạo SSL + debug
# -----------------------------
install_noVNC() {
  dstat "Clone noVNC..."
  run_container "git clone https://github.com/h3l2f/noVNC1 /home/container/noVNC1 || echo 'WARNING: git clone noVNC thất bại'"

  dstat "Tạo chứng chỉ SSL..."
  run_container "
    cd /home/container/noVNC1 && \
    openssl req -x509 -sha256 -days 365 -nodes -newkey rsa:2048 \
      -subj '/CN=localhost/C=US/L=Local' -keyout self.key -out self.crt || echo 'WARNING: openssl tạo SSL thất bại'; \
    cp vnc.html index.html
  "
}

# -----------------------------
# Tải Android-x86 ISO + debug
# -----------------------------
download_android_iso() {
  dstat "Tải Android-x86 ISO..."
  run_container "wget -c $ANDROID_ISO_URL -O $ANDROID_ISO || echo 'WARNING: wget Android-x86 ISO thất bại'"
}

# -----------------------------
# Khởi chạy noVNC + Android-x86 + debug
# -----------------------------
start_vnc_and_vm() {
  dstat "Khởi chạy noVNC server..."
  run_container "cd /home/container/noVNC1 && ./utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $WEB_PORT &"
  echo "✔ Web noVNC: http://<HOST-IP>:$WEB_PORT"
  echo "✔ RealVNC client: connect to <HOST-IP>:$VNC_PORT"

  dstat "Khởi chạy Android-x86 live ISO với GPU ảo..."
  run_container "
    echo '==> Chạy QEMU Android-x86...';
    qemu-system-x86_64 -m $MEMORY -smp $CPUS \
      -boot d -cdrom $ANDROID_ISO \
      -vga virtio -display sdl,gl=on \
      -usbdevice tablet \
      -netdev user,id=net0,hostfwd=tcp::$HOSTFWD_PORT-:8000 \
      -device virtio-net-pci,netdev=net0 \
      -display vnc=127.0.0.1:$((VNC_PORT-5900)) || echo 'WARNING: QEMU chạy lỗi'
  "
}

# -----------------------------
# Main
# -----------------------------
dstat "Bắt đầu setup Android-x86 VM debug..."
check_cmd wget
check_cmd tar
check_cmd git
check_cmd python3
check_cmd pip

bootstrap_proot
bootstrap_rootfs
install_packages
install_noVNC
download_android_iso
start_vnc_and_vm

dstat "Setup hoàn tất!"
