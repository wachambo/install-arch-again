#!/usr/bin/env bash

#TODO
# templates with big files. Custom them with config variables using sed and
# copy them into directories (instead of cat<<HERE ......)

# TODO
# LVM and LUKS

# License:  This  program  is  free  software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published by
# the  Free Software Foundation; either version 3 of the License, or (at your
# option)  any later version. This program is distributed in the hope that it
# will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
# Public License for more details.

# Title  : iaa.sh: [i]nstall [a]rch [a]gain
# Brief  : script for installing Arch Linux automatically
# Author : Alejandro Blasco
# Usage  : edit iaa.conf and run ./iaa.sh

# Set a temporay keymap (maybe for edditing this script)
# do: # loadkeys 'keymap'

set -e
set -u

# Some global vars
unset log tty
log='./iaa.log'
tty=$(tty)

error_conf()
{
  printf "\033[1;31m%s\n\033[1;0m" "Error in var configuration $1" | tee -a  $log
  exit 1
}
error()
{
  printf "\033[1;31m%s\n\033[1;0m" "Error: $@" | tee -a  $log
  exit 1
}
info()
{
  printf "%s\n" "$@" | tee $tty
}
alert()
{
  printf "\033[1;31m%s\n\033[1;0m" "$@" | tee $tty
}
run_root()
{
  arch-chroot /mnt "$@"
}
run_root_file()
{
  local filename=$1
  while read cmd; do
    arch-chroot /mnt "$cmd"
  done < $filename
}

trap 'umount -R /mnt; exit 1' SIGHUP SIGINT SIGQUIT SIGTERM ERR


# INSTALLATION {{{
begin_installation()
{
  alert '         Starting installation'
  alert '         ---------------------'
}

check_requirements()
{
  info 'Checking requirements'

  # Check root user id
  (( $EUID == 0 )) || error 'please run as root user'

  # Check Arch linux
  [[ -e /etc/arch-release ]] || error 'please run on arch linux'

  # Arch-install-scripts required (pacstrap, arch-chroot)
  type pacstrap &> /dev/null || error 'missing package: arch-install-scripts'

  # gdisk required (gdisk, cgdisk, sgdisk)
  type gdisk &> /dev/null || error 'missing package: gptfdisk'
}

check_configuration()
{
  info 'Checking configurations'
  source ./iaa.conf &> /dev/null || \
    error "missing configuration file iaa.conf in $(pwd)"

  # Check review
  case $review in
    yes)
      if ! type "$EDITOR" > /dev/null; then
        alert "  $EDITOR not fond. Automatically changed to EDITOR='vi'"
        EDITOR='vi'
      fi
      ;;
    *)
      review='no' ;;
  esac

  # Partitioning
  [[ $swap =~ yes|no ]] || error_conf 'swap'
  [[ $home =~ yes|no ]] || error_conf 'home'

  # Check 'dest_disk' is really a disk
  [[ -z $dest_disk ]] && error_conf 'dest_disk'
  [[ $(lsblk -dno TYPE $dest_disk) == 'disk' ]] || error_conf 'dest_disk'

  # Check /mnt for availability
  if mountpoint /mnt &> /dev/null; then
    error 'working directory /mnt is blocked by mounted filesystem \
    do: $ umount -R /mnt'
  fi

  # Check dest_disk for mounted filesystems
  if mount | grep "$dest_disk" &> /dev/null; then
    error 'found mounted filesystem on destination disk \
    do: $ umount -R /mnt'
  fi

  ## Check swap_size
  if [[ $swap = 'yes' ]]; then
    [[ $swap_size =~ [0-9]+[K,M,G,T] ]]  || error_conf 'swap_size'
  fi

  ## Check root_size
  if [[ $root_size != '0' ]]; then
    [[ $root_size =~ [0-9]+[K,M,G,T] ]] || error_conf 'root_size'
  else
    [[ "$home" = 'yes' ]] && error_conf 'home'
  fi

  ## Check home_size
  if [[ $home_size != '0' ]]; then
    [[ $home_size =~ [0-9]+[K,M,G,T] ]] || error_conf 'home_size'
  fi

  # Check File system
  # Refer to https://wiki.archlinux.org/index.php/File_systems
  ## Check if mkfs utilities are installed
  ## set options for overwriting existing filesystems
  case $fstype in
    btrfs)
      type mkfs.btrfs > /dev/null || error 'missing package: btrfs-progs'
      packages+=( 'btrfs-progs' )
      mkfs_options="$fstype -q"
      ;;
    ext2|ext3|ext4)
      type mkfs.ext4 > /dev/null || error 'missing package: e2fsprogs'
      mkfs_options="${fstype} -q"
      ;;
    f2fs)
      type mkfs.f2fs > /dev/null || error 'missing package: f2fs-tools'
      packages+=( 'f2fs-tools' )
      mkfs_options="$fstype -q"
      ;;
    jfs)
      type mkfs.jfs > /dev/null || error 'missing package: jfsutils'
      mkfs_options="${fstype} -q"
      ;;
    nilfs2)
      type mkfs.nilfs2 > /dev/null || error 'missing package: nilfs-utils'
      packages+=( 'nilfs-utils' )
      mkfs_options="${fstype} -q -f"
      ;;
    reiserfs)
      type mkfs.reiserfs > /dev/null || error 'missing package: reiserfsprogs'
      mkfs_options="${fstype} -q"
      ;;
    xfs)
      type mkfs.xfs > /dev/null || error 'missing package: xfsprogs'
      mkfs_options="${fstype} -q -f"
      ;;
    *)
      error_conf 'fstype';;
  esac

  # Check BIOS or UEFI
  case $uefi in
    no)
      ## BIOS supports Grub and Syslinux
      case $bootloader in
        grub|syslinux) ;;
        *)
          info 'Set Grub as bootloader'
          bootloader='grub' ;;
      esac

      # boot_size
      [[ -z $boot_size ]] && error_conf 'boot_size'
      [[ $boot_size =~ [0-9]+[K,M,G,T] ]] || error_conf 'boot_size'
      ;;
    *)
      ## UEFI supports Grub, Systemd-boot (gummiboot), EFISTUB and rEFInd
      case $bootloader in
        grub|systemd-boot|gummiboot|efistub|reifnd) ;;
        *)
          info 'Set Grub as bootloader'
          bootloader='grub' ;;
      esac

      ## check if install host is booted in uefi mode
      if [[ -z "$(mount --types=efivarfs)" ]]; then
        mount --types=efivarfs /sys/firmware/efi/efivars || error_conf 'uefi'
      fi
      efivar -l || error_conf 'uefi'

      type mkfs.vfat || error 'missing package: dosfstools'

      # ESP size recommedation
      # (https://wiki.archlinux.org/index.php/Unified_Extensible_Firmware_Interface_(Espa%C3%B1ol)#EFI_System_Partition)
      esp_size='256M'
      ;;
  esac

  # Check locale
  if ! grep "$locale" /etc/locale.gen &> /dev/null; then
    error_conf 'locale'
  fi

  # Check keymap
  #TODO, bug reported
  #[[ $(localectl list-keymaps) =~ "$keymap" ]] || error_conf 'keymap'
  [[ -n ${keymap} && ${keymap} =~ [a-z_\.\ \-]+ ]] || error_conf 'keymap'
  ## Load keymap for installation
  loadkeys ${keymap}

  # Check x11-layout
  # (cannot vaalidate other options in this step)
  [[ -n $x11_layout && $x11_layout =~ [a-z][a-z] ]] || error_conf 'x11_layout'

  # Check timezone
  [[ -n $timezone && $(timedatectl list-timezones) =~ "$timezone" ]] || error_conf 'timezone'

  # Check hardware_clock
  [[ -n $hardware_clock && $hardware_clock =~ utc|localtime ]] || error_conf 'hardware_clock'

  # Check hostname
  [[ -n $hostname && $hostname =~ [a-z0-9][a-z0-9-]*[a-z0-9] ]] || error_conf 'hostname'

  # Check username
  [[ -z $username ]] && error_conf 'username'

  # Check sudo
  [[ $sudo =~ yes|no ]] || error_conf 'sudo'

  # Check login shell
  [[ -z $login_shell ]] && login_shell='bash'
  case $login_shell in
    sh|bash|tcsh|dash|fish|ksh|nash|oh|powershell|rc|xonsh|zsh) ;;
    *) error_conf 'login_shell' ;;
  esac

  # Check Video driver
  [[ -z $video_driver ]] && error_conf 'video_driver'
  case $video_driver in
    amd|ati|intel|nouveau|nvidia|virtualbox|vmware) ;;
    *) error_conf 'video_driver' ;;
  esac

  # Check Xorg
  ## Check desktop_environment
  [[ -z $window_manager ]] && error_conf 'window_manager'
  case $window_manager in
    #TODO complete
    no|cinnamon|enlightenment|gnome|i3|kde|lxde|mate|xfce)  ;;
    *) error_conf 'window_manager' ;;
  esac

  ## Check display_manager
  [[ -z $display_manager ]] && error_conf 'display_manager'
  case $display_manager in
    no|gdm|kdm|sddm|lightdm|lxdm|mdm|slim|xdm) ;;
    *) error_conf 'display_manager' ;;
  esac

  ## Check network_manager
  [[ -z $network_manager ]] && error_conf 'network_manager'
  case $network_manager in
    no|connman|dhcpd|netctl|networkmanager|systemd-networkd|wicd) ;;
    *) error_conf 'network_manager' ;;
  esac
}

check_internet()
{
  info 'Checking internet connection'
  ping -c 1 -W 5  8.8.8.8 || error 'no internet connection! :S'
}

make_part()
{
  # Refer to https://wiki.archlinux.org/index.php/Partitioning
  alert '---------------------------------------'
  alert 'The following drive will be formatted'
  local devs=$(lsblk --output=NAME,TYPE,MODEL,SIZE,FSTYPE "$dest_disk")
  alert "$devs"
  alert '---------------------------------------'

  # Ask confirmation
  local answer='x'
  while [[ $answer != 'Y' ]]; do
    printf 'Continue? (Y/n) ' | tee $tty
    read -n 2 -r answer
    [[ $answer = 'n' ]] && error 'script cancelled'
    printf '\n'
  done

  # Prepare disk
  info 'Preparing disk'
  sgdisk --zap-all $dest_disk
  dd bs=1K count=1024 iflag=nocache oflag=direct if=/dev/zero of=$dest_disk
  wipefs --all $dest_disk
  blockdev --rereadpt $dest_disk; sync; blockdev --rereadpt $dest_disk
  sgdisk --verify $dest_disk || error 'disk corrupt'

  # Partition layout
  local esp_num=0
  local boot_num=0
  local swap_num=0
  root_num=0 # Global because it's read in install_bootloader func
  local home_num=0
  if [[ $uefi = 'yes' ]]; then
    if [[ $swap = 'yes' ]]; then
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
    if [[ $swap = 'yes' ]]; then
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

  # TODO support also Linux ARM partitions

  # Simulate partitions
  info 'Simulating partitioning'
  ## EFI system/BIOS boot partition
  if [[ $uefi = 'yes' ]]; then
    sgdisk --new=${esp_num}:0:+${esp_size} \
      --typecode=${esp_num}:EF00 $dest_disk \
      --change-name=${esp_num}:ESP \
      --pretend $dest_disk || error 'ESP'
  else
    sgdisk --new=${boot_num}:0:+${boot_size} \
      --typecode=${boot_num}:EF02 $dest_disk \
      --change-name=${boot_num}:boot \
      --pretend $dest_disk || error '/boot'
  fi

  ## Swap partition
  if [[ $swap = 'yes' ]]; then
    sgdisk --new=${swap_num}:0:+${swap_size} \
      --typecode=${swap_num}:8200 $dest_disk \
      --change-name=${swap_num}:swap \
      --pretend $dest_disk || error 'swap'

  fi

  ## Root partition
  sgdisk --new=${root_num}:0:+${root_size} \
    --typecode=${root_num}:8303 $dest_disk \
    --change-name=${root_num}:root \
    --pretend $dest_disk || error '/root'

  ## Home partition
  if [[ $home = 'yes' ]]; then
    sgdisk --new=${home_num}:0:+${home_size} \
      --typecode=${home_num}:8302 $dest_disk \
      --change-name=${home_num}:home \
      --pretend $dest_disk || error '/home'
  fi

  # Perform partitions
  info 'Creating partitions'

  ## EFI system/BIOS boot partition
  if [[ $uefi = 'yes' ]]; then
    info '  ESP'
    sgdisk --new=${esp_num}:0:+${esp_size} \
      --typecode=${esp_num}:EF00 $dest_disk \
      --change-name=${esp_num}:ESP
    sleep 1
  else
    info '  /boot'
    sgdisk --new=${boot_num}:0:+${boot_size} \
      --typecode=${boot_num}:EF02 $dest_disk \
      --change-name=${boot_num}:boot
    sleep 1
  fi

  ## Swap partition
  if [[ $swap = 'yes' ]]; then
    info '  swap'
    sgdisk --new=${swap_num}:0:+${swap_size} \
      --typecode=${swap_num}:8200 $dest_disk \
      --change-name=${swap_num}:swap
    sleep 1
  fi

  ## Root partition
  info '  / (root)'
  sgdisk --new=${root_num}:0:+${root_size} \
    --typecode=${root_num}:8303 $dest_disk \
    --change-name=${root_num}:root
  sleep 1

  ## Home partition
  if [[ "$home" == 'yes' ]]; then
    info '  /home'
    sgdisk --new=${home_num}:0:+${home_size} \
      --typecode=${home_num}:8302 $dest_disk \
      --change-name=${home_num}:home
    sleep 1
  fi

  # Partition summary
  sgdisk --verify $dest_disk || error 'disk corrupt'
  sgdisk --print $dest_disk

  # Create and mount filesystems
  info 'Formatting and Mounting partitions'

  ## Root
  info '  / (root)'
  mkfs.${mkfs_options} ${dest_disk}${root_num}
  mount --types=$fstype ${dest_disk}${root_num} /mnt

  ## ESP/BIOS
  if [[ $uefi = 'yes' ]]; then
    info '  ESP'
    mkfs.vfat -F32 ${dest_disk}${esp_num}
    mkdir -p /mnt/boot
    mount --options=nodev,nosuid,noexec --types=vfat ${dest_disk}${esp_num} /mnt/boot
  else
    info '  /boot'
    mkfs.ext2 -q ${dest_disk}${boot_num}
    mkdir -p /mnt/boot
    mount --options=nodev,nosuid,noexec --types=ext2 ${dest_disk}${boot_num} /mnt/boot
  fi

  ## Swap
  if [[ $swap = 'yes' ]]; then
    info '  swap'
    mkswap ${dest_disk}${swap_num}
    swapon ${dest_disk}${swap_num}
  fi

  ## Home
  info '  /home'
  mkfs.${mkfs_options} ${dest_disk}${home_num}
  mkdir /mnt/home
  mount --options=nodev,nosuid --types=$fstype ${dest_disk}${home_num} /mnt/home

  # Increase cowspace partition
  mount --options=remount,size=2G /run/archiso/cowspace
}

install_base()
{
  info 'Installing base system packages (be patient...)'
  pacstrap /mnt base
}

generate_fstab()
{
  # Refer to https://wiki.archlinux.org/index.php/Fstab
  info 'Generatig Mounting File System Table'
  genfstab -t UUID -P /mnt > /mnt/etc/fstab
  cat /mnt/etc/fstab
}
# INSTALLATION }}}


begin_post_installation()
{
  alert '      Starting Post-installation'
  alert '      --------------------------'
}

# {{{ POST INSTALL: from here, all in the new filesystem
pacman_install()
{
  pacman \
    --root=/mnt \
    --noconfirm \
    --needed \
    --cachedir=/var/cache/pacman/pkg \
    --sync "$@"
}

set_locale()
{
  # Refer to https://wiki.archlinux.org/index.php/Locale
  info '  System Locale'

  # Before a locale can be enabled on the system, it must be generated
  sed -i "/#${locale}/s//${locale}/" /mnt/etc/locale.gen
  run_root "locale-gen"

  # Set the system locale
  cat <<HERE | tee /mnt/etc/locale.conf
LANG=${locale}
LC_COLLATE=C
HERE
}

set_virtual_console()
{
  # Refer to https://wiki.archlinux.org/index.php/Keyboard_configuration_in_console
  info '  Virtual console keymap'
  cat <<HERE | tee /mnt/etc/vconsole.conf
KEYMAP=${keymap}
HERE
}

set_timezone()
{
  # Refer to https://wiki.archlinux.org/index.php/Timezone
  info '  Timezone'
  ln -sf /usr/share/zoneinfo/$timezone /mnt/etc/localtime

  # NOTE: symbolic names points to the future post-installation locaation,
  # not the actual locaation (under /mnt) ;-)
}

set_hardware_clock()
{
  info '  Hardware clock'
  hwclock --systohc --adjfile=/mnt/etc/adjtime --$hardware_clock
  cat /mnt/etc/adjtime
}

add_kernel_modules()
{
  # TODO intall headers before...
  info '  Kernel modules'
  if [[ -n $k_modules ]]; then
    for m in ${k_modules[@]}; do
      echo "$m" >> /mnt/etc/modules-load.d/modules.conf
    done
  fi
}

set_hostname()
{
  # Refer to https://wiki.archlinux.org/index.php/Network_configuration#Set_the_hostname
  info '  Host name'
  echo "$hostname" > /mnt/etc/hostname
  sed -i "/127.0.0.1/s/$/\t ${hostname}/" /mnt/etc/hosts
  sed -i "/::1/s/$/\t ${hostname}/" /mnt/etc/hosts
  cat /mnt/etc/hosts
}

set_network_manager()
{
  # Refer to https://wiki.archlinux.org/index.php/Network_configuration
  info ' Network manager'
  info '  Wired network'
  local wired_dev=$( ls /sys/class/net | grep en )
  if [[ -z $wired_dev ]]; then
    alert '  No wired device'
  fi
  #wired_dev=$( ip link \
  #  | egrep "en[a-z][0-9]" \
  #  | awk '{print $2}' \
  #  | sed 's/://' \
  #  | head -1 \
  #)

  info '  Wifi network'
  local wifi_dev=$( ls /sys/class/net | grep wl )
  if [[ -z $wifi_dev ]]; then
    alert '  No wifi device'
  fi
  #wifi_dev=$( ip link \
  #  | egrep "wl[0-9]" \
  #  | awk '{print $2}' \
  #  | sed 's/://' \
  #  | head -1
  #)

  case $network_manager in
    connman)
      # TODO
      ;;

    dhcpd)
      # Enable network service (dhcpcd)
      #ip link  ???

      ## Wired net
      if [[ -n $wired_dev ]]; then
          run_root systemctl enable dhcpcd@${wired_dev}.service
          run_root systemctl start  dhcpcd@${wired_dev}.service
      fi

      ## Try wifi
      if [[ -n $wifi_dev ]]; then
          run_root wifi-menu -o $wifi_dev
      fi

      [[ -z $wired_dev && -z $wifi_dev ]] && error 'Cant find any network device'
      return 0
      ;;

    netctl)
      # TODO
      ;;

    networkmanager)
      # Install
      pacman_install networkmanager

      run_root systemctl enable NetworkManager.service
      run_root systemctl start  NetworkManager.service
      ;;

    no|systemd-networkd)
      # https://wiki.archlinux.org/index.php/Systemd-networkd

      ## Wired net
      if [[ -n $wired_dev ]]; then
        cat <<HERE | tee /mnt/etc/systemd/network/20-wired.network
[Match]
Name=$wired_dev

[Network]
DHCP=ipv4

[DHCP]
RouteMetric=10
HERE
      fi

      ## Try wifi
      if [[ -n $wifi_dev ]]; then
        cat <<HERE | tee /mnt/etc/systemd/network/25-wireless.network
[Match]
Name=$wifi_dev

[Network]
DHCP=ipv4

[DHCP]
RouteMetric=10
HERE
      fi

      [[ -z $wired_dev && -z $wifi_dev ]] && error 'Cant find any network device'
      run_root systemctl enable systemd-networkd.service
      run_root systemctl enable systemd-resolved.service
      return 0
      ;;

    wicd)
      # TODO
      ;;

    *) ;;
  esac
}

set_root_password()
{
  # Refer to https://wiki.archlinux.org/index.php/Reset_root_password
  info '  Password for root user'
  if [[ -z $root_password ]]; then
    if ! run_root passwd root; then
      error "Incorrect password for $username"
    fi
  else
    printf "root:${root_password}\n" | run_root chpasswd
  fi
}

add_user()
{
  # Refer to https://wiki.archlinux.org/index.php/users_and_groups
  info "  Password for ${username}"
  run_root useradd --create-home --gid=users \
    --shell=/bin/$login_shell $username
  if [[ -z $user_password ]]; then
    run_root passwd -d $username
  else
    printf "${username}:${user_password}\n" | run_root chpasswd
  fi

  if [[ $sudo = 'yes' ]]; then
    # Add $username to group 'wheel' and allow its members to execute any command
    # Refer to https://wiki.archlinux.org/index.php/sudo#Using_visudo
    pacman_install sudo
    run_root usermod --append --groups wheel ${username}
    run_root sed -i '/%wheel ALL=(ALL) ALL/s/^#//' /etc/sudoers
  fi
}

set_mirrors()
{
  # Refer to https://wiki.archlinux.org/index.php/Mirrors
  info '  Fastest mirrors (be patient...)'
  cp -f /mnt/etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist.bak
  rankmirrors -n 6 /mnt/etc/pacman.d/mirrorlist.bak > /mnt/etc/pacman.d/mirrorlist
}

make_initial_ramdisk()
{
  # Refer to https://wiki.archlinux.org/index.php/Mkinitcpio
  info '  Initial RAM disk'
  run_root mkinitcpio --config=/etc/mkinitcpio.conf \
    --generatedir=/boot --preset=linux
}

install_bootloader()
{
  # Refer to: https://wiki.archlinux.org/index.php/Bootloader
  info 'Installing bootloader (be patient...)'

  local partuuid=$(blkid -s PARTUUID -o value ${dest_disk}${root_num})
  local uuid=$(blkid -s UUID -o value ${dest_disk}${root_num})

  case $bootloader in
    grub)
      # Refer to https://wiki.archlinux.org/index.php/GRUB

      # Install
      pacman_install dosfstools efibootmgr grub

      # Configure
      if [[ $uefi = 'yes' ]]; then
        ## UEFI
        run_root grub-install --target=x86_64-efi \
          --efi-directory=/boot \
          --bootloader-id=grub \
          --recheck
        run_root grub-mkconfig --output=/boot/grub/grub.cfg

        # Workaround for Virtualbox bug in UEFI mode
        # https://wiki.archlinux.org/index.php/VirtualBox#Installation_in_EFI_mode
        if [[ $video_driver = 'virtualbox' ]]; then
          mkdir -p /mnt/boot/EFI/boot
          cp /mnt/boot/EFI/grub/grubx64.efi /mnt/boot/EFI/boot/bootx64.efi
        fi
      else
        ## BIOS
        run_root grub-install --target=i386-pc \
          --recheck ${dest_disk}
        run_root grub-mkconfig --output=/boot/grub/grub.cfg
      fi
      cat /mnt/boot/grub/grub.cfg
      ;;

    systemd-boot|gummibot)
      # Refer to: https://wiki.archlinux.org/index.php/Systemd-boot

      # Install
      run_root bootctl --path=/boot install
      mkdir -p /mnt/boot/loader/entries

      # Configure
      rm /mnt/boot/loader/loader.conf &> /dev/null
      cat <<HERE | tee /mnt/boot/loader/loader.conf
default arch
timeout 4
editor  1
HERE

      cat <<HERE | tee /mnt/boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=$uuid rw splash
HERE

      # Hook for automatically updating every time the systemd pkg is upgraded
      mkdir -p /mnt/etc/pacman.d/hooks/
      cat <<HERE | tee /mnt/etc/pacman.d/hooks/systemd-boot.hook
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot...
When = PostTransaction
Exec = /usr/bin/bootctl --path=/boot update
HERE
      ;;

    syslinux)
      # Refer to: https://wiki.archlinux.org/index.php/Syslinux

      # Install
      pacman_install gptfdisk syslinux
      mkdir -p /mnt/boot/syslinux
      cp /mnt/usr/lib/syslinux/bios/*.c32 /mnt/boot/syslinux/ || \
        error 'copying *.c32 files'
      run_root extlinux --install /boot/syslinux/ || error 'installing Syslinux'
      ## Mark boot partition as "active"
      sgdisk --attributes=1:set:2 ${dest_disk} || \
        error 'setting bit 2 of the attributes for /boot partition'
      ## Install the MBR
      dd bs=440 conv=notrunc count=1 if=/mnt/usr/lib/syslinux/bios/gptmbr.bin \
        of=${dest_disk} || error 'installing MBR'
      ## Download a splash screen
      curl \
        http://ftp.sleepgate.ru/pxe/archiso/current/boot/syslinux/splash.png \
        -o /mnt/boot/syslinux/splash.png || error 'splash url not found'

      # Configure
      cat <<HERE | tee /mnt/boot/syslinux/syslinux.cfg
UI vesamenu.c32
DEFAULT arch
PROMPT 0
MENU TITLE Boot Menu
MENU BACKGROUND splash.png
TIMEOUT 50

MENU WIDTH 78
MENU MARGIN 4
MENU ROWS 5
MENU VSHIFT 10
MENU TIMEOUTROW 13
MENU TABMSGROW 11
MENU CMDLINEROW 11
MENU HELPMSGROW 16
MENU HELPMSGENDROW 29

# Refer to http://www.syslinux.org/wiki/index.php/Comboot/menu.c32
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #30ffffff #00000000 std

#PROMPT 1
#TIMEOUT 50
#DEFAULT arch

LABEL arch
  MENU LABEL Arch Linux
  LINUX ../vmlinuz-linux
  APPEND root=UUID=$uuid rw
  INITRD ../initramfs-linux.img

LABEL archfallback
  MENU LABEL Arch Linux [Fallback]
  LINUX ../vmlinuz-linux
  APPEND root=UUID=$uuid rw
  INITRD ../initramfs-linux-fallback.img
HERE
      ;;

    efistub)
      #TODO
      ;;

    refind)
      #TODO
      ;;

    *)
      # Never reached
      ;;
  esac
}

install_video_card_driver()
{
  # Refer to https://wiki.archlinux.org/index.php/xorg#Driver_installation
  [[ -z $video_driver ]] && return 0
  info 'Installing video card driver'
  case $video_driver in
    amd)
      #TODO untested
      # Refer to: https://wiki.archlinux.org/index.php/AMDGPU
      # Install driver 2D in Xorg and driver 3D
      pacman_install xf86-video-amdgpu mesa
      ;;
    ati)
      #TODO untested
      # Refer to: https://wiki.archlinux.org/index.php/ATI
      # Install driver 2D in Xorg and driver 3D
      pacman_install xf86-video-ati mesa
      ;;
    intel)
      # Refer to: https://wiki.archlinux.org/index.php/Intel_graphics
      # Install driver 2D in Xorg and driver 3D
      pacman_install xf86-video-intel mesa

      # Install microcode
      # Refer to: https://wiki.archlinux.org/index.php/microcode
      pacman_install intel-ucode
      case $bootloader in
        grub)
          # regenerate the GRUB config
          run_root grub-mkconfig --output=/boot/grub/grub.cfg
          ;;
        systemd-boot|gummibot)
          # new initrd line with intel-code.img
          sed -i '/^linux.*/a\initrd  \/intel-ucode.img' /mnt/boot/loader/entries/arch.conf
          ;;
        syslinux)
          #TODO untested
          # append intel-code.img to initrd
          sed -i 's/^  INITRD /  INITRD ../intel-ucode.img,/' /mnt/boot/syslinux/syslinux.cfg
          ;;
        efistub)
          #TODO
          ;;
        refind)
          #TODO
          ;;
        *) ;;
      esac
      ;;
    nouveau)
      #TODO untested
      # Refer to: https://wiki.archlinux.org/index.php/Nouveau
      # Install driver 2D in Xorg and driver 3D
      pacman_install xf86-video-nouveau mesa
      ;;
    nvidia)
      #TODO
      # Refer to: https://wiki.archlinux.org/index.php/NVIDIA
      ;;
    virtualbox)
      # Refer to: https://wiki.archlinux.org/index.php/VirtualBox#Installation_steps_for_Arch_Linux_guests
      # Install driver 2D in Xorg and driver 3D
      pacman_install xf86-video-vesa mesa
      # Install guest additions
      pacman_install virtualbox-guest-utils virtualbox-guest-modules-arch
      # Load VBox kernel modules automatically
      run_root systemctl enable vboxservice.service
      ;;
    vmware)
      # Refer to: https://wiki.archlinux.org/index.php/VMware/Installing_Arch_as_a_guest
      # Install driver 2D in Xorg and driver 3D
      pacman_install xf86-video-vmware mesa
      # Install mouse driver and vmware tools
      pacman_install xf86-input-vmmouse open-vm-tools
      run_root systemctl enable vmware-vmblock-fuse.service
      ;;
  esac
}

install_xorg()
{
  # Refer to: https://wiki.archlinux.org/index.php/xorg
  info 'Installing Xorg server'
  pacman_install xorg-server
  # TODO: Additionally, some packages from the xorg-apps group may be necessary

  # Configure Xorg keymap
  # Refer to: https://wiki.archlinux.org/index.php/Keyboard_configuration_in_Xorg#Using_X_configuration_files
  info '  Xorg keymap'
  #localectl --no-convert set-x11-keymap \
    #  ${x11_layout} ${x11_model} ${x11_variant} ${x11_options} || \
    #  error 'Xorg keymap'
  #cat /etc/X11/xorg.conf.d/00-keyboard.conf

  mkdir -p /mnt/etc/X11/xorg.conf.d
  mv /mnt/etc/X11/xorg.conf.d/00-keyboard.conf \
    /mnt/etc/X11/xorg.conf.d/00-keyboard.conf.bak || true
  cat <<HERE | tee /mnt/etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
  Identifier "system-keyboard"
  MatchIsKeyboard "on"
  Option "XkbLayout" "${x11_layout}"
  Option "XkbModel" "${x11_model}"
  Option "XkbVariant" ",${x11_variant}"
  Option "XkbOptions" "${x11_options}"
EndSection
HERE
}

install_window_manager()
{
  # Install window manager/desktop environment
  # Refer to https://wiki.archlinux.org/index.php/Window_manager
  # Refer to https://wiki.archlinux.org/index.php/Desktop_environment
  info '  Installing Window Manager/Desktop Environment'

  case $window_manager in
    no)       alert 'Nothing to install' ;;
    cinnamon) pacman_install cinnamon ;;
    enlightenment)
      pacman_install enlightenment ;;
    gnome)    pacman_install gnome-shell gnome-control-center ;;
    i3)       pacman_install i3 dmenu ;;
    kde)      pacman_install plasma plasma-wayland-session ;;
    lxde)     pacman_install lxde ;;
    mate)     pacman_install mate ;;
    xfce)     pacman_install xfce4 xfce4-goodies ;;
  esac
}

install_display_manager()
{
  # Install display manager
  # Refer to https://wiki.archlinux.org/index.php/Display_manager
  info '  Installing Display manager'

  case $display_manager in
    no)
      alert 'Nothing to install'
      _configure_xinitrc
      ;;
    *)
      pacman_install $display_manager
      run_root systemctl enable ${display_manager}.service
      ;;
  esac
}

_configure_xinitrc()
{
  # Refer to https://wiki.archlinux.org/index.php/xinitrc
  info 'Configuring xinitrc'
  pacman_install xorg-xinit
  #TODO!! the skeletom of xinitrc is shit and must be not copied.
  # It contains automatic execution of 'twm' or 'xterm' even if
  # you didn't install them
  #cp -fv /mnt/etc/X11/xinit/xinitrc /mnt/home/${username}/.xinitrc
  local session
  session=$(case $window_manager in
    enlightenment) echo 'enlightenment_start' ;;
    cinnamon) echo 'cinnamon-session' ;;
    gnome)    echo 'gnome-session' ;;
    i3)       echo 'i3' ;;
    kde)      echo 'startkde' ;;
    lxde)     echo 'startlxde' ;;
    mate)     echo 'mate-session' ;;
    xfce)     echo 'startxfce4' ;;
    # TODO Add more...
  esac)
  echo -e "exec $session" >> /mnt/home/${username}/.xinitrc

  #if [[ $video_driver == 'virtualbox' ]]; then
  #  # Launch automatically all VBox guest services
  #  echo "/usr/bin/VBoxClient-all" >> /mnt/home/${username}/.xinitrc

  #  # To enable shared folders:
  #  #https://wiki.archlinux.org/index.php/VirtualBox#Enable_shared_folders
  #fi

  run_root chown ${username}:users /home/${username}/.xinitrc
}

install_additional_packages()
{
  info 'Installing additional packages (be patient...)'
  # Load package list from file pkglist.txt
  if [[ -s ./pkglist.txt ]]; then
    local packages+=( $( < ./pkglist.txt ) )
  fi
  pacman_install ${packages[@]} || true
}

extra_configurations()
{
  info 'Performing extra configurations...'
  # Execute other scripts
  for f in *.sh; do
    if [[ ${f} == ${0##*/} || ${f} == _* ]]; then
      continue
    elif [[ ${f} == root_* ]]; then
      # Run the script as root
      run_root_file ${f}
    else
      # Run the script
      bash ${f}
    fi
  done
}

review_configurations()
{
  [[ $review = 'no' ]] && return 0

  echo 'Review configurations'
  # Ask confirmation
  local answer='x'
  while [[ $answer != 'Y' ]]; do
    printf 'Continue? (Y/n) '
    read -n 2 -r answer
    [[ $answer = 'n' ]] && return 0
    printf '\n'
  done

  # Mounting FileSystem Table
  $EDITOR /mnt/etc/fstab

  # Locale
  $EDITOR /mnt/etc/locale.conf

  # Virtual console
  $EDITOR /mnt/etc/vconsole.conf

  # Hardware clock
  $EDITOR /mnt/etc/adjtime

  # Kernel modules
  $EDITOR /mnt/etc/modules-load.d/modules.conf

  # Hostname
  $EDITOR /mnt/etc/hosts

  # Mirror list
  $EDITOR /mnt/etc/pacman.d/mirrorlist

  # Initial RAM disk
  $EDITOR /mnt/etc/mkinitcpio.conf

  # Bootloader
  case $bootloader in
    grub)  $EDITOR /mnt/etc/default/grub ;;
    syslinux) $EDITOR /mnt/boot/syslinux/syslinux.cfg ;;
    *) ;;
  esac

  # Xorg keyboard
  $EDITOR /mnt/etc/X11/xorg.conf.d/00-keyboard.conf

  # Xinitrc
  $EDITOR /mnt/home/${username}/.xinitrc
}

end_installation()
{
  info 'Unmounting filesystems'
  umount --recursive /mnt

  alert '---------------------------------------'
  alert '        Installation completed! (*)'
  alert '     Reboot the computer: # reboot'
  alert '---------------------------------------'
}
# END POST-INSTALL }}}



main()
{
  > $log

  {
    check_requirements
    check_configuration
    check_internet

    begin_installation
    make_part
    install_base
    generate_fstab

    begin_post_installation
    set_locale
    set_virtual_console
    set_timezone
    set_hardware_clock
    #TODO
    #add_kernel_modules
    set_hostname
    set_network_manager
    set_root_password
    add_user
    set_mirrors
    make_initial_ramdisk
    install_bootloader
    install_video_card_driver
    install_xorg
    install_window_manager
    install_display_manager
    install_additional_packages
    extra_configurations
  } &>> $log

  review_configurations
  end_installation &>> $log
}

main "$@"
exit 0


# vim: set ai ts=2 sw=2 sts=2 tw=80 et ft=sh :
