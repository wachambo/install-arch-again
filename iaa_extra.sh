#!/usr/bin/env bash

# Some global vars
unset log
log='./iaa.log'

error_conf()
{
  printf "\033[1;31m%s\n\033[1;0m" "Error in var configuration $1"
  printf "%s\n" "Error in var configuration $1" >> $log
  exit 1
}

error()
{
  printf "\033[1;31m%s\n\033[1;0m" "Error: $@"
  printf "%s\n" "Error: $@" >> $log
  exit 1
}

info()
{
  printf "%s\n" "$@"
  printf "%s\n" "$@" >> $log
}

alert()
{
  printf "\033[1;31m%s\n\033[1;0m" "$@"
  printf "%s\n" "$@" >> $log
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
