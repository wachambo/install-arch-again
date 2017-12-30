#!/bin/env bash

echo
echo 'Downloading files...'

for f in iaa.sh iaa_extra.sh \
  iaa-test.conf iaa-gnome.conf pkglist-gtk.txt \
  _virtualbox.sh _services.sh; do
  echo $f
  curl -fOLs "https://gitlab.com/wachambo/install-arch-again/raw/test/${f}"
  [ $? != '0' ] && echo 'Error' && exit 1
done
mv iaa-test.conf iaa.conf

for f in *; do
  [[ ! -f "$f" ]] && continue

  if [[ "$f" == *.sh ]]; then
    chmod 755 "$f"
  else
    chmod 644 "$f"
  fi
done

echo
echo 'Done!'
echo 'Edit iaa.conf and pkglist.txt (see exaples) and then run ./iaa.sh'
echo

exit 0
