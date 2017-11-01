#!/bin/env sh

echo
echo 'Downloading files...'

for f in iaa.sh iaa-test.conf; do
  echo $f
  curl -fOLs "https://gitlab.com/wachambo/install-arch-again/raw/test/${f}"
  [ $? != '0' ] && echo 'Error' && exit 1
done
mv iaa-test.conf iaa.conf

chmod 755 iaa.sh
chmod 644 iaa.conf

echo
echo 'Done!'
echo 'Edit iaa.conf and pkglist.txt (see exaples) and then run ./iaa.sh'
echo

exit 0
