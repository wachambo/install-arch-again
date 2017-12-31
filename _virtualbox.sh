#!/usr/bin/env bash

source ./iaa.conf
source ./iaa_extra.sh

run_root usermod -a -G vboxsf $username

case $display_manager in
no)
  echo "/usr/bin/VBoxClient-all" >> /mnt/home/${username}/.xinitrc
  ;;
*)
  mkdir -p /mnt/home/${username}/.config/autostart/
  cp /mnt/etc/xdg/autostart/vboxclient.desktop /mnt/home/${username}/.config/autostart/
  ;;
esac
