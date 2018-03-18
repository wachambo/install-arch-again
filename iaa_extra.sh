#!/usr/bin/env bash

# Some global vars
unset log tty
log='./iaa.log'
tty=$(tty)

info()
{
  printf "%s\n" "[ INFO] $@" > $tty
  printf "%s\n" "[ INFO] $@" >> $log
}

warn()
{
  printf "\033[1;31m%s\n\033[1;0m" "[ WARN] $@" > $tty
  printf "%s\n" "[ WARN] $@" >> $log
}

error_conf()
{
  printf "\033[1;31m%s\n\033[1;0m" "[ERROR] var configuration $1" > $tty
  printf "%s\n" "[ERROR] var configuration $1" >> $log
  exit 1
}

error()
{
  printf "\033[1;31m%s\n\033[1;0m" "[ERROR] $@" > $tty
  printf "%s\n" "[ERROR] $@" >> $log
  exit 1
}

run_root()
{
  arch-chroot /mnt "$@"
}

#run_root_file()
#{
#  local filename=$1
#  while read cmd; do
#    arch-chroot /mnt "$cmd"
#  done < $filename
#}
