#!/bin/env sh

echo 'Downloading files...'
for f in iaa.sh iaa.conf pkglist.txt; do
  echo $f
  curl -fOLs "https://raw.github.com/wachambo/install-arch-again/master/${f}"
  [ $? != '0' ] && echo 'Error' && exit 1
done
chmod 755 iaa.sh
chmod 644 iaa.conf
chmod 644 pkglist.txt
echo 'Done!'
exit 0
