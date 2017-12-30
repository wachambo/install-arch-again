#!/usr/bin/env bash

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
#run_root_file()
#{
#  local filename=$1
#  while read cmd; do
#    arch-chroot /mnt "$cmd"
#  done < $filename
#}
