#!/bin/bash
# Android-x86 9.0 live session chạy bằng Proot + QEMU + noVNC
# GPU ảo Virtio + 3D acceleration
# Bỏ VirtualGL, cài openssl + pip, fix tất cả lỗi package

# -----------------------------
# Cấu hình
# -----------------------------
mirror_alpine_main="http://dl-cdn.alpinelinux.org/alpine/v3.22/main"
mirror_alpine_community="http://dl-cdn.alpinelinux.org/alpine/v3.22/community"
mirror_proot="https://proot.gitlab.io/proot/bin/proot"
install_path="./android_vm"
android_iso="$install_path/android-x86_64-9.0-r2.iso"
VNC_PORT=5900       # VNC server port trong container
WEB_PORT=6080       # Web noVNC port
MEMORY=2048         # RAM VM
CPUS=$(nproc --all) # Số core CPU

# -----------------------------
# Hàm hỗ trợ
# -----------------------------
dstat() { echo -e "\033[1;37m==> \033[1;34m$@\033[0m"; }
die() { echo -e "\033[41mFATAL ERROR. Exit.\033[0m"; exit 1; }

# -----------------------------
# Bootstrap Alpine + Proot
# -----------------------------
bootstrap() {
  dstat "Tải Alpine rootfs..."
  mkdir -p "$install_path"
  curl -L "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.2-x86_64.tar.gz" -o "$install_path/alpine.tar.gz" || die
  tar -xf "$install_path/alpine.tar.gz" -C "$install_path" || die
  rm "$install_path/alpine.tar.gz"

  dstat "Tải dockerd (Proot)..."
  curl -L "$mirror_proot" -o "$install_path/dockerd" || die
  chmod +x "$install_path/dockerd"

  mkdir -p "$install_path/home/container"
  
  # Fix DNS/Hosts
  cp /etc/resolv.conf "$install_path/etc/resolv.conf" -v
  cp /etc/hosts "$install_path/etc/hosts" -v
}

# -----------------------------
# Chạy lệnh trong Proot
# -----------------------------
run_container_cmd() {
  env HOME="$install_path/home/container" \
    $install_path/dockerd --kill-on-exit \
    -r "$install_path" -b /dev -b /proc -b /sys -b /tmp \
    -b "$install_path":"$install_path" /bin/sh -c "$1"
}

# -----------------------------
# Cài noVNC + Websockify + QEMU
# -----------------------------
install_inside() {
  dstat "Cập nhật APK và cài package cần thiết..."
  run_container_cmd "
    apk update --repository=$mirror_alpine_main --repository=$mirror_alpine_community && \
    apk add --no-cache bash wget git qemu qemu-system-x86_64 unzip python3 py3-pip openssl mesa-dri-gallium websockify xvfb
  " || die

  dstat "Cài websockify bằng pip..."
  run_container_cmd "pip install --break-system-packages websockify" || die

  dstat "Clone noVNC..."
  run_container_cmd "
    git clone https://github.com/h3l2f/noVNC1 /home/container/noVNC1 && \
    cd /home/container/noVNC1 && \
    openssl req -x509 -sha256 -days 365 -nodes -newkey rsa:2048 \
      -subj '/CN=localhost/C=US/L=Local' -keyout self.key -out self.crt && \
    cp vnc.html index.html
  " || die

  dstat "Tải Android x86 ISO..."
  run_container_cmd "wget https://downloads.sourceforge.net/project/android-x86/Release%209.0/android-x86_64-9.0-r2.iso -O $android_iso" || die
}

# -----------------------------
# Khởi chạy VNC + Android VM với GPU ảo
# -----------------------------
start_vnc_and_vm() {
  dstat "Khởi chạy noVNC server (web)..."
  run_container_cmd "
    cd /home/container/noVNC1 && \
    ./utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $WEB_PORT &
  " || die

  echo "✔ Web noVNC: http://<HOST-IP>:$WEB_PORT"
  echo "✔ RealVNC client: connect to <HOST-IP>:$VNC_PORT"

  dstat "Khởi chạy Android-x86 live ISO với GPU ảo..."
  run_container_cmd "
    qemu-system-x86_64 -m $MEMORY -smp $CPUS \
      -boot d -cdrom $android_iso \
      -vga virtio -display sdl,gl=on \
      -usbdevice tablet \
      -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
      -display vnc=127.0.0.1:$((VNC_PORT-5900))
  " || die
}

# -----------------------------
# Main
# -----------------------------
bootstrap
install_inside
start_vnc_and_vm
