# Enable autologin for $username
sed -i "s/^User=$/User=${username}/" /mnt/etc/sddm.conf

# Plasma session
sed -i "s/^Session=$/Session=plasma.desktop/" /mnt/etc/sddm.conf

# Theme breeze
sed -i "s/^Current=$/Current=breeze/" /mnt/etc/sddm.conf
