#!/usr/bin/env bash

source ./iaa_extra.sh

# Uncomment Misc options
for opt in UseSyslog Color TotalDownload CheckSpace VerbosePkgLists; do
  sed -i "/$opt/s/^#//g" /mnt/etc/pacman.conf
done

# Add ILoveCandy option
sed -i '/VerbosePkgLists/a ILoveCandy' /mnt/etc/pacman.conf
