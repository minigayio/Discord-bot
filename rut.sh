#!/bin/bash
# Copyright(C) 2025 Lemem Developers. All rights reserved.

# >> User-Configuration  <<
user_passwd="$(echo "$HOSTNAME" | sed 's+-.*++g')"
retailer_mode=false
retailer_prod="enabled retailer mode as an example"
# [ Mirrors ]
mirror_alpine="https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.2-x86_64.tar.gz"
mirror_proot="https://proot.gitlab.io/proot/bin/proot"
#  >> Runtime configuration <<
if "$retailer_mode"; then install_path=$HOME/.subsystem; elif [ -n "$SERVER_PORT" ]; then install_path="$HOME/cache/$(echo "$HOSTNAME" | md5sum | sed 's+ .*++g')"; else install_path="./testing-arena"; fi

d.stat() { echo -ne "\033[1;37m==> \033[1;34m$@\033[0m\n"; }

die() {
  echo -ne "\n\033[41m               \033[1;37mA FATAL ERROR HAS OCCURED               \033[0m\n"
  echo -ne "\033[1;31mThe installation cannot continue. Please contact the server administrator.\033[0m\n"
  sleep 5
  exit 1
}

# <dbgsym:bootstrap>
check_link="curl --output /dev/null --silent --head --fail"
bootstrap_system() {

  _CHECKPOINT=$PWD

  d.stat "Initializing the Alpine rootfs image..."
  curl -L "$mirror_alpine" -o a.tar.gz && tar -xf a.tar.gz || die
  rm -rf a.tar.gz

  d.stat "Downloading a Docker Daemon..."
  curl -L "$mirror_proot" -o dockerd || die
  chmod +x dockerd

  d.stat "Bootstrapping system..."
  touch etc/{passwd,shadow,groups}

  # coppy files
  cp /etc/resolv.conf "$install_path/etc/resolv.conf" -v
  cp /etc/hosts "$install_path/etc/hosts" -v
  cp /etc/localtime "$install_path/etc/localtime" -v
  cp /etc/passwd "$install_path"/etc/passwd -v
  cp /etc/group "$install_path"/etc/group -v
  cp /etc/nsswitch.conf "$install_path"/etc/nsswitch.conf -v
  mkdir -p "$install_path/home/container"
  mkdir -p "$install_path/shared/windows"
  
  d.stat "Downloading will took 5-15 minutes.."
./dockerd -r . -b /dev -b /sys -b /proc -b /tmp \
    --kill-on-exit -w /home/container /bin/sh -c "apk update && apk add bash xorg-server git nano unzip python3 virtiofsd py3-pip py3-numpy openssl \
      xinit xvfb fakeroot qemu qemu-img qemu-system-x86_64 \
    virtualgl mesa-dri-gallium \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main; \
    git clone https://github.com/h3l2f/noVNC1 && \
    cd noVNC1 && \
    openssl req -x509 -sha256 -days 356 -nodes -newkey rsa:2048 -subj '/CN=$(curl -L checkip.pterodactyl-installer.se)/C=US/L=San Fransisco' -keyout self.key -out self.crt && \
    cp vnc.html index.html && \
    ln -s /usr/bin/fakeroot /usr/bin/sudo && \
    pip install websockify --break-system-packages && \
     wget https://cdn.lememhost.cloud/windows10.zip && \
   