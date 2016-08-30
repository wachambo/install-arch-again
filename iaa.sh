#!/bin/bash

# License:  This  program  is  free  software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published by
# the  Free Software Foundation; either version 3 of the License, or (at your
# option)  any later version. This program is distributed in the hope that it
# will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
# Public License for more details.

# title  : iaa.sh: [i]nstall [a]rch [a]gain
# brief  : script for installing Arch Linux automatically
# author : Alejandro Blasco
# usage  : edit iaa.conf and run ./iaa.sh

# colors
unset ALL_OFF GREEN RED
ALL_OFF='\e[1;0m'
GREEN='\e[1;32m'
RED='\e[1;31m'
readonly ALL_OFF GREEN RED


# functions
# {{{
error_conf() {
  printf "${RED}%s\n${ALL_OFF}" "Error in var configuration $1"
  exit 1
}

error() {
  printf "${RED}%s\n${ALL_OFF}" "Error, $1"
  exit 1
}

begin_installer() {
  printf "$RED"
  cat << EOF
---------------------------------------
  Starting installation
---------------------------------------
EOF
  printf "$ALL_OFF"
  pause 3

  # chroots to the new system environment!!
  arch-chroot /mnt
}

end_installer() {
  # exit the chroot environment and come back to .iso!!
  exit

  printf "Unmounting filesystems...\n"
  umount -R /mnt

  printf "$RED"
  cat << EOF
---------------------------------------
        Installation completed!
     Reboot the computer: # reboot
---------------------------------------
EOF
  printf "$ALL_OFF"
  exit 0
}

check_requirements() {
  # check root user id
  [ "$EUID" = '0' ] || error "please run as root user"

  # check arch linux
  [ -e /etc/arch-release ] || error "please run on arch linux"

  # arch-install-scripts required
  type pacstrap > /dev/null || error "missing package: arch-install-scripts"
  # gdisk required
  type gdisk > /dev/null || error "missing package: gptfdisk"
}

check_configuration() {
  printf "${GREEN}Checking configurations ...\n${ALL_OFF}"

  # source configuration file if it is in the current working directory
  if [ -s ./iaa.conf ]; then
    . ./iaa.conf
  else
    error "configuration file iaa.conf not found in $(pwd)"
  fi

  # edit_conf
  case "edit_conf" in
    yes)type "$EDITOR" > /dev/null || error_conf 'EDITOR' ;;
    no) ;;
    *)  error_conf 'edit_conf' ;;
  esac

  # unmount
  echo "$unmount" | egrep -x 'yes|no' > /dev/null || error_conf 'unmount'

  # partitioning
  echo "$swap" | egrep -x 'yes|no' > /dev/null || error_conf 'swap'
  echo "$home" | egrep -x 'yes|no' > /dev/null || error_conf 'home'

  # dest_disk is really a disk
  [ -z "$dest_disk" ] && error_conf 'dest_disk'
  [ $(lsblk -dno TYPE "$dest_disk") = 'disk' ] || error_conf 'dest_disk'

  # check /mnt for availability
  mountpoint -q /mnt && error "working directory /mnt is blocked by mounted filesystem"

  # check dest_disk for mounted filesystems
  mount | grep "$dest_disk" > /dev/null && error "found mounted filesystem on destination disk"

  ## swap_size
  if [ "$swap" = 'yes' ]; then
    echo "$swap_size" | egrep '^[0-9]+[K,M,G,T]$' > /dev/null || error_conf 'swap_size'
  fi

  # root_size
  if [ "$root_size" != '0' ]; then
    echo "$root_size" | egrep '^[0-9]+[K,M,G,T]$' > /dev/null || error_conf 'root_size'
  else
    [ "$home" = 'yes' ] && error_conf 'home'
  fi

  ## home_size
  if [ "$home_size" != '0' ]; then
    echo "$home_size" | egrep '^[0-9]+[K,M,G,T]$' > /dev/null || error_conf 'home_size'
  fi

  # fstype
  # https://wiki.archlinux.org/index.php/File_systems
  ## check if mkfs utilities are installed
  ## set options for overwriting existing filesystems
  case "$fstype" in
    btrfs)
      type mkfs.btrfs > /dev/null || error 'missing package: btrfs-progs'
      packages+=( 'btrfs-progs' )
      mkfs_options="$fstype"
      ;;
    ext2|ext3|ext4)
      type mkfs.ext4 > /dev/null || error 'missing package: e2fsprogs'
      mkfs_options="${fstype} -q"
      ;;
    f2fs)
      type mkfs.f2fs > /dev/null || error 'missing package: f2fs-tools'
      packages+=( 'f2fs-tools' )
      mkfs_options="$fstype"
      ;;
    jfs)
      type mkfs.jfs > /dev/null || error 'missing package: jfsutils'
      mkfs_options="${fstype} -q"
      ;;
    nilfs2)
      type mkfs.nilfs2 > /dev/null || error 'missing package: nilfs-utils'
      packages+=( 'nilfs-utils' )
      mkfs_options="${fstype} -f -q"
      ;;
    reiserfs)
      type mkfs.reiserfs > /dev/null || error 'missing package: reiserfsprogs'
      mkfs_options="${fstype} -q"
      ;;
    xfs)
      type mkfs.xfs > /dev/null || error 'missing package: xfsprogs'
      mkfs_options="${fstype} -f -q"
      ;;
    *)
      error_conf 'fstype';;
  esac

  # uefi
  case "$uefi" in
    yes)
      ## check if install host is booted in uefi mode
      if [ -z "$(mount -t efivarfs)" ]; then
        mount -t efivarfs efivarfs /sys/firmware/efi/efivars > /dev/null ||
         error_conf 'uefi'
      fi
      efivar -l > /dev/null || error_conf 'uefi'
      ## UEFI only allows Grub since Syslinux automatic installation is only available for BIOS
      echo "$bootloader" | egrep -x 'grub' > /dev/null || error_conf 'bootloader'
      type mkfs.vfat > /dev/null || error 'missing package: dosfstools'

      # ESP size
      echo "$esp_size" | egrep - '^[0-9]+[K,M,G,T]$' > /dev/null || error_conf 'esp_siz'
      ;;
    no)
      ## BIOS supports Syslinux and Grub
      echo "$bootloader" | egrep -x 'syslinux|grub' > /dev/null || error_conf 'bootloader'

      # boot_size
      echo "$boot_size" | egrep '^[0-9]+[K,M,G,T]$' > /dev/null || error_conf 'boot_size'
      ;;
    *)
      error_conf 'uefi'
      ;;
  esac

  # locale: enforce UTF-8
  echo "$locale" | egrep '^[a-z]{2,3}_[A-Z]{2}(.UTF-8)?\ UTF-8$' > /dev/null || error_conf 'locale'

  # keymap
  localectl --no-pager list-keymaps | grep -x "$keymap" > /dev/null || error_conf 'keymap'
  ## load keymap for installation
  loadkeys ${keymap}

  # font
  [ -z "$font" ] && font='cp850-8x16'

  # timezone
  timedatectl --no-pager list-timezones | grep -x "$timezone" > /dev/null || error_conf 'timezone'

  # hardware_clock
  echo "$hardware_clock" | egrep -x 'utc|localtime' > /dev/null || error_conf 'hardware_clock'

  # hostname
  echo "$hostname" | egrep '^[a-z0-9][a-z0-9-]*[a-z0-9]$' > /dev/null || error_conf 'hostname'

  # username
  [ -z "$username" ] && error_conf 'username'

  # xorg
  ## desktop_environment
  case "$window_manager" in
    no|i3|cinnamon|enlightenment|gnome|kde|lxde|mate|xfce4)  ;;
    *)  error_conf 'window_manager' ;;
  esac
  ### display_manager
  case "$display_manager" in
    no|gdm|kdm|lxdm|xdm)  ;;
    *)  error_conf 'display_manager' ;;
  esac

  # no config_fail beyond this point
  printf "${GREEN}\nEverything was fine :)\n${ALL_OFF}"
}

check_internet() {
  printf "Checking internet connection ...\n"
  ping -c 1 -W 5  8.8.8.8 > /dev/null || error "no internet connection"
  printf "${GREEN}OK\n${ALL_OFF}"
}

make_part() {
  # https://wiki.archlinux.org/index.php/Partitioning
  # ask confirmation
  printf "$RED"
  printf "---------------------------------------\n"
  printf "The following drive will be formatted\n"
  lsblk -o NAME,TYPE,MODEL,SIZE,FSTYPE "$dest_disk"
  printf "---------------------------------------\n"
  printf "$ALL_OFF"

  local answer='x'
  while [ "$answer" != 'Y' ]; do
    printf "Continue? (Y/n) "
    read -n 2 -r answer
    [ "$answer" = 'n' ] && error 'script cancelled'
    printf '\n'
  done

  # prepare disk
  printf "Preparing disk ...\n"
  sgdisk -Z "$dest_disk"
  dd bs=1K count=1024 iflag=nocache oflag=direct if=/dev/zero of="$dest_disk"
  wipefs -a "$dest_disk"
  blockdev --rereadpt "$dest_disk"; sync; blockdev --rereadpt "$dest_disk"

  # partition layout
  printf "Creating partitions ...\n"
  if [ "$uefi" = yes ]; then
    if [ "$swap" = 'yes' ]; then
      esp_num=1
      swap_num=2
      root_num=3
      home_num=4
    else
      esp_num=1
      root_num=2
      home_num=3
    fi
  else
    if [ "$swap" = 'yes' ]; then
      boot_num=1
      swap_num=2
      root_num=3
      home_num=4
    else
      boot_num=1
      root_num=2
      home_num=3
    fi
  fi

  ## EFI system/BIOS boot partition
  if [ "$uefi" = 'yes' ]; then
    sgdisk -n "$esp_num":0:+"$esp_size" -t "$esp_num":EF00 "$dest_disk"
    sleep 1
  else
    sgdisk -n "$boot_num":0:+"$boot_size" -t "$boot_num":8300 "$dest_disk"
    sleep 1
  fi

  ## swap partition
  if [ "$swap" = 'yes' ]; then
    sgdisk -n "$swap_num":0:+"$swap_size" -t "$swap_num":8200 "$dest_disk"
    sleep 1
  fi

  ## root partition
  sgdisk -n "$root_num":0:+"$root_size" -t "$root_num":8300 "$dest_disk"
  sleep 1

  ## home partition
  if [ "$home" = 'yes' ]; then
    sgdisk -n "$home_num":0:+"$home_size" -t "$home_num":8300 "$dest_disk"
    sleep 1
  fi

  # create and mount filesystems
  ## root
  printf "Formatting root ...\n"
  mkfs.${mkfs_options} "${dest_disk}${root_num}"
  printf "Mounting root ...\n"
  mount -t "$fstype" "${dest_disk}${root_num}" /mnt

  ## ESP/BIOS
  if [ "$uefi" = 'yes' ]; then
    printf "Formatting ESP ...\n"
    mkfs.vfat -F32 "${dest_disk}${esp_num}"
    mkdir -p /mnt/boot
    printf "Mounting ESP ...\n"
    mount -o nodev,nosuid,noexec -t vfat "${dest_disk}${esp_num}" /mnt/boot
  else
    printf "Formatting /boot..\n"
    mkfs.ext2 -q "${dest_disk}${boot_num}"
    mkdir -p /mnt/boot
    printf "Mounting /boot ...\n"
    mount -o nodev,nosuid,noexec -t ext2 "${dest_disk}${boot_num}" /mnt/boot
  fi

  ## swap
  if [ "$swap" = 'yes' ]; then
    printf "Formatting swap ...\n"
    mkswap "${dest_disk}${swap_num}"
    swapon "${dest_disk}${swap_num}"
  fi

  ## home
  printf "Formatting /home ...\n"
  mkfs.${mkfs_options} "${dest_disk}${home_num}"
  mkdir /mnt/home
  printf "Mounting /home ...\n"
  mount -o nodev,nosuid -t "$fstype" "${dest_disk}${home_num}" /mnt/home
}

pacman_install() {
  # TODO pacman --noconfirm --needed -r /mnt --cachedir=/mnt/var/cache/pacman/pkg -S $@
  pacman --noconfirm --needed --cachedir=/var/cache/pacman/pkg -S $@
}

install_base() {
  printf "Installing base system packages ...\n"
  pacstrap /mnt base
}

install_bootloader() {
  # https://wiki.archlinux.org/index.php/Bootloader
  printf "Installing bootloader...\n"

  if [ "$bootloader" = 'grub' ]; then
    # https://wiki.archlinux.org/index.php/GRUB
    ## install grub package
    pacman_install dosfstools efibootmgr grub

    ## configure grub
    if [ "$edit_conf" = 'yes' ]; then
      "$EDITOR" /etc/default/grub
      clear
    fi

    ## run grub-mkconfig and grub-install
    if [ "$uefi" = 'yes' ]; then
      ## UEFI
      grub-mkconfig -o /boot/grub/grub.cfg
      grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=arch_grub --recheck
    else
      ## BIOS
      grub-mkconfig -o /boot/grub/grub.cfg
      grub-install --target=i386-pc --recheck ${dest_disk}
    fi
  else
    # https://wiki.archlinux.org/index.php/Syslinux
    ## install syslinux package
    pacman_install gptfdisk syslinux

    ## run syslinux-install_update
    syslinux-install_update -i -a -m

    ## configure syslinux: not need since it's done by syslinux-install_update
#    local root_partuuid=$(lsblk -dno PARTUUID "${dest_disk}${root_num}")
#    local cmdline="root=PARTUUID=${root_partuuid} rw"
#    cat << EOF > /boot/syslinux/syslinux.cfg
#PROMPT 1
#TIMEOUT 50
#DEFAULT arch
#
#LABEL arch
#LINUX ../vmlinuz-linux
#APPEND ${cmdline}
#INITRD ../initramfs-linux.img
#
#LABEL archfallback
#LINUX ../vmlinuz-linux
#APPEND ${cmdline}
#INITRD ../initramfs-linux-fallback.img
#EOF
    if [ "$edit_conf" = 'yes' ]; then
      "$EDITOR" /boot/syslinux/syslinux.cfg
      clear
    fi
  fi
}

configure_system() {
  printf "Configuring system ...\n"

  # fstab
  # https://wiki.archlinux.org/index.php/Fstab
  printf "Generating mounting filesystem ...\n"
  genfstab -U -p / > /etc/fstab
  if [ "$edit_conf" = 'yes' ]; then
    "$EDITOR" /etc/fstab
    clear
  fi

  # locale
  # https://wiki.archlinux.org/index.php/Locale
  cat << EOF > /etc/locale.conf
LANG=${locale}
EOF

  # console font and keymap
  # https://wiki.archlinux.org/index.php/Keyboard_configuration_in_console
  cat << EOF > /etc/vconsole.conf
KEYMAP=${keymap}
FONT=${font}
EOF

  # timezone
  # https://wiki.archlinux.org/index.php/Timezone
  ln -s /usr/share/zoneinfo/"$timezone" /etc/localtime

  # hardware clock
  hwclock --adjfile=/etc/adjtime -w --"$hardware_clock"

  # kernel modules
  if [ -n "$k_modules" ]; then
    for m in ${k_modules[@]}; do
      printf "${m}\n" >> /etc/modules-load.d/modules.conf
    done
  fi

  # hostname
  # https://wiki.archlinux.org/index.php/Network_configuration#Set_the_hostname
  printf "${hostname}\n" > /etc/hostname
  sed -i "/127.0.0.1/s/$/\t ${host_name}/" /etc/hosts

  # network service (dhcpcd)
  printf "Enabling wired network ...\n"
  ## reverting tradicional names (https://wiki.archlinux.org/index.php?title=Network_configuration&redirect=no#Change_device_name)
  ln -s /dev/null /etc/udev/rules.d/80-net-setup-link.rules
  ## wired net
  local _wired_dev=$(ip link | egrep "eth[0-9]" | awk '{print $2}' | sed 's/://' | head -1)
  systemctl enable "${network}@${_wired_dev}.service" > /dev/null
  systemctl start "${network}@${_wired_dev}.service" > /dev/null
  ## try wifi
  local _wifi_dev=$(ip link | egrep "eth[0-9]" | awk '{print $2}' | sed 's/://' | head -1)
  [ -n $_wifi_dev ] && wifi-menu -o $_wifi_dev

  #  mkinitcpio
  # https://wiki.archlinux.org/index.php/Mkinitcpio
  printf "Creating an initial RAM disk ...\n"
  mkinitcpio -p linux

  # root password
  printf "Setting password for root user ... \n"
  if [ -z "$root_password" ]; then
    while true; do
      if passwd root; then
        break
      fi
    done
  else
    printf "root:${root_password}\n" | chpasswd
  fi

  # add user
  # https://wiki.archlinux.org/index.php/users_and_groups
  useradd -m -g users -s /bin/"$login_shell" "$username"
  printf "Setting password for ${username} ...\n"
  if [ -z "$user_password" ]; then
    while true; do
      if passwd "$username"; then
        break
      fi
    done
  else
    printf "${username}:${user_password}\n" | chpasswd
  fi

  # https://wiki.archlinux.org/index.php/Mirrors
  printf "Installing fastest mirrors ...\n"
  cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
  rankmirrors -n 6 mirrorlist.bak > mirrorlist
}

install_xorg() {
  # https://wiki.archlinux.org/index.php/xorg
  printf "Installing xorg packages ...\n"
  pacman_install xorg-server xorg-server-utils xorg-utils

  # install window manager/desktop environment
  # https://wiki.archlinux.org/index.php/Window_manager
  # https://wiki.archlinux.org/index.php/Desktop_environment
  printf "Installing Window Manager/Desktop Environment ...\n"
  case "$window_manager" in
    no)    printf "${RED}no\n${ALL_OFF}"
    i3)    pacman_install i3 dmenu
    *)     ;;
    # add more...
  esac

  # install display manager
  # https://wiki.archlinux.org/index.php/Display_manager
  printf "Installing Display manager ...\n"
  case "$display_manager" in
    no)    printf "${RED}no\n${ALL_OFF}" ;;
    *)     ;;
    # add more...
  esac

  # configure xinitrc
  # https://wiki.archlinux.org/index.php/xinitrc
  pacman_install xorg-xinit
  printf "Configuring xinitrc ...\n"
  cp -fv /etc/X11/xinit/xinitrc /home/${username}/.xinitrc
  echo -e "exec ${window_manager}" >> /home/${username}/.xinitrc
  chown -R ${username}:users /home/${username}/.xinitrc
}

install_additional_packages() {
  printf "Installing additional packages...\n"
  # load package list from file pkglist.txt
  if [ -s ./pkglist.txt ]; then
    local _packages+=( $( < ./pkglist.txt ) )
    pacman_install ${_packages[@]} || true
  fi
}
# }}}






# main
# {{{
set -e -u
[ -z "$EDITOR" ] && EDITOR='vi'

check_requirements
check_configuration
check_internet
make_part
install_base
begin_installer
install_bootloader
configure_system
install_xorg
install_additional_packages
end_installer
# }}}
