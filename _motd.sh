#!/usr/bin/env bash

# Print a message of the day after a succesful login
# Refer to: https://wiki.archlinux.org/index.php/Arch_boot_process#Message_of_the_day

> /mnt/etc/motd

echo "                                         " >> /mnt/etc/motd
echo "  ________        __               __    " >> /mnt/etc/motd
echo " |  |  |  |.----.|  |--..--------.|  |--." >> /mnt/etc/motd
echo " |  |  |  ||  __||     ||        ||  _  |" >> /mnt/etc/motd
echo " |________||____||__|__||__|__|__||_____|" >> /mnt/etc/motd
echo " Welcome!                                " >> /mnt/etc/motd