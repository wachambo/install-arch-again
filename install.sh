#!/bin/env sh

echo
echo 'Downloading files...'

for f in iaa.sh iaa.conf iaa-i3.conf iaa-kde.conf pkglist.txt pkglist-gtk.txt pkglist-qt.txt; do
  echo $f
  curl -fOLs "https://raw.github.com/wachambo/install-arch-again/master/${f}"
  [ $? != '0' ] && echo 'Error' && exit 1
done

chmod 755 iaa.sh
for f in iaa.conf iaa-i3.conf iaa-kde.conf pkglist.txt pkglist-gtk.txt pkglist-qt.txt; do
  chmod 644 $f
done

echo
echo 'Done!'
echo 'Edit iaa.conf and pkglist.txt (see exaples) and then run ./iaa.sh'
echo

exit 0
