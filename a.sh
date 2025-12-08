#!/bin/bash
# Copyright(C) 2025 Lemem Developers. All rights reserved.
# ANDROID-X86 9.0-r2 LIVE + noVNC ĐẸP NHẤT (h3l2f/noVNC1) + WEB + REALVNC

set -e

# ========================== CẤU HÌNH ==========================
retailer_mode=false
if "$retailer_mode"; then 
  install_path=$HOME/.subsystem
elif [ -n "$SERVER_PORT" ]; then 
  install_path="\( HOME/cache/ \)(echo "$HOSTNAME" | md5sum | awk '{print $1}')"
else 
  install_path="./android-x86-live"      # thư mục sẽ tạo ra
fi

# ========================== HÀM ==========================
dstat() { echo -e "\033[1;37m==> \033[1;34m$@\033[0m"; }
die()   { echo -e "\n\033[41m FATAL ERROR OCCURRED \033[0m"; exit 1; }

# ========================== SETUP (chỉ chạy lần đầu) ==========================
bootstrap_system() {
  mkdir -p "$install_path"
  cd "$install_path"

  dstat "Tải Alpine Linux rootfs..."
  curl -L "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.2-x86_64.tar.gz" -o rootfs.tar.gz
  tar -xf rootfs.tar.gz
  rm rootfs.tar.gz

  dstat "Tải PROOT từ link bạn gửi..."
  curl -L "https://proot.gitlab.io/proot/bin/proot" -o dockerd
  chmod +x dockerd

  dstat "Cài gói + tải Android-x86 ISO + noVNC ĐẸP (h3l2f/noVNC1)..."
  ./dockerd -r . -b /dev -b /proc -b /sys -b /tmp -b /dev/dri \
    --kill-on-exit -w /home/container /bin/sh -c "
    apk update
    apk add --no-cache bash git openssl qemu-system-x86_64 mesa-dri-gallium websockify

    # DÙNG ĐÚNG REPO BẠN GỬI → GIAO DIỆN WEB CỰC ĐẸP
    mkdir -p /home/container
    git clone https://github.com/h3l2f/noVNC1 /home/container/noVNC1

    cd /home/container/noVNC1
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout self.key -out self.crt -subj '/CN=localhost' >/dev/null 2>&1
    # SSL tự ký
    cp vnc.html index.html

    # Tải Android-x86 9.0-r2 ISO (LIVE)
    mkdir -p /shared
    cd /shared
    wget -O android.iso \
      'https://sourceforge.net/projects/android-x86/files/Release%209.0/android-x86_64-9.0-r2.iso/download'
  "
}

# ========================== CHẠY HỆ THỐNG ==========================
DOCKER_RUN="env - HOME=$install_path/home/container $install_path/dockerd --kill-on-exit -r $install_path -b /dev -b /proc -b /sys -b /tmp -b /dev/dri -b $install_path:$install_path /bin/sh -c"

run_system() {
  cd "$install_path"

  WEB_PORT="${SERVER_PORT:-6080}"

  # 1. Khởi động noVNC Web (dùng h3l2f/noVNC1 – đẹp nhất hiện nay)
  dstat "Khởi động giao diện Web noVNC (h3l2f/noVNC1) trên port $WEB_PORT..."
  $install_path/dockerd --kill-on-exit -r $install_path -b /dev -b /proc -b /sys -b /tmp -b /dev/dri \
    -w /home/container/noVNC1 /bin/sh -c "
    ./utils/novnc_proxy \
      --vnc localhost:5901 \
      --listen 0.0.0.0:$WEB_PORT \
      --cert self.crt \
      --key self.key \
      --web . &
  " &>/dev/null &

  sleep 5

  # In link đẹp để bạn dán subdomain
  IP=$(curl -s ifconfig.me || echo "YOUR_IP")
  echo -e "\n\033[1;32m══════════════════════════════════════════\033[0m"
  echo -e "   ANDROID-X86 9.0-R2 LIVE SẴN SÀNG!"
  echo -e "   \033[1;33mWeb (noVNC đẹp nhất):\033[0m"
  echo -e "   → http://$IP:$WEB_PORT"
  echo -e "   → https://$IP:$WEB_PORT      (SSL tự ký – chấp nhận cảnh báo là vào)"
  echo -e "   \033[1;33mRealVNC / TigerVNC / bất kỳ app VNC:\033[0m"
  echo -e "   → $IP:5901    (hoặc subdomain:5901)"
  echo -e "\033[1;32m══════════════════════════════════════════\033[0m\n"

  # 2. Khởi động Android-x86 LIVE + GPU ảo + VNC thật port 5901
  dstat "Khởi động Android-x86 9.0-r2 LIVE + VirtIO-GPU..."
  $DOCKER_RUN "
    qemu-system-x86_64 \\
      -m 4096 -smp $(nproc) -cpu max \\
      -machine q35 \\
      -boot d -cdrom /shared/android.iso \\
      -device virtio-gpu-pci,virgl=on \\
      -display gtk,gl=on,show-cursor=on \\
      -vnc 0.0.0.0:1 \\                     # mở VNC thật ra ngoài port 5901
      -usb -device usb-tablet \\
      -netdev user,id=net0,hostfwd=tcp::5555-:5555 \\
      -device virtio-net-pci,netdev=net0 \\
      -rtc base=utc,clock=host \\
      -soundhw ac97
  "

  # Nếu QEMU crash thì rơi vào shell để debug
  $DOCKER_RUN bash
}

# ========================== MAIN ==========================
mkdir -p "$install_path"
cd "$install_path"

if [ -f dockerd ] && [ -d home/container/noVNC1 ]; then
  run_system
else
  bootstrap_system
  run_system
fi
