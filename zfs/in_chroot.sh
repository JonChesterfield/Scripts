#!/bin/bash

set -e
set -x
set -o pipefail


id=`id -u`
if [ $id = "0" ]
then
    echo "Running as root"
else
    echo "Meant to run as root"
    exit 1
fi


if [ "$#" -ne 0 ]; then
    echo "Check arguments, expected none"
    ls /dev/disk/by-id
    exit 1
fi

echo "Disk = $DISK"

apt update
apt install --yes console-setup locales

echo "Want en_US.UTF-8"

dpkg-reconfigure locales tzdata 


apt install --yes dpkg-dev linux-headers-generic linux-image-generic
apt install --yes zfs-initramfs
echo REMAKE_INITRD=yes > /etc/dkms/zfs.conf

# time
apt install systemd-timesyncd

apt install dosfstools

mkdosfs -F 32 -s 1 -n EFI ${DISK}-part2
mkdir /boot/efi
echo /dev/disk/by-uuid/$(blkid -s UUID -o value ${DISK}-part2) \
   /boot/efi vfat defaults 0 0 >> /etc/fstab
# Mount seems to fail if done immediately after the fstab, try leaving it a few seconds
# todo, presumably should be reloading something
sleep 3
mount /boot/efi
apt install --yes grub-efi-amd64 shim-signed

apt purge --yes os-prober

passwd

cat <<EOF > /etc/systemd/system/zfs-import-bpool.service
[Unit]
DefaultDependencies=no
Before=zfs-import-scan.service
Before=zfs-import-cache.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/zpool import -N -o cachefile=none bpool
# Work-around to preserve zpool cache:
ExecStartPre=-/bin/mv /etc/zfs/zpool.cache /etc/zfs/preboot_zpool.cache
ExecStartPost=-/bin/mv /etc/zfs/preboot_zpool.cache /etc/zfs/zpool.cache

[Install]
WantedBy=zfs-import.target

EOF

systemctl enable zfs-import-bpool.service


apt install --yes openssh-server iw tasksel git

# temporary
sed -i 's$#PermitRootLogin prohibit-password$PermitRootLogin yes # todo, undo this...$g' /etc/ssh/sshd_config

grub-probe /boot
update-initramfs -c -k all


sed -i 's$GRUB_CMDLINE_LINUX=""$GRUB_CMDLINE_LINUX="root=ZFS=rpool/ROOT/debian"$' /etc/default/grub

sed -i 's$GRUB_CMDLINE_LINUX_DEFAULT="quiet"$GRUB_CMDLINE_LINUX_DEFAULT=""$' /etc/default/grub

sed -i 's$#GRUB_TERMINAL=console$GRUB_TERMINAL=console$' /etc/default/grub

update-grub


grub-install --target=x86_64-efi --efi-directory=/boot/efi \
     --bootloader-id=debian --recheck --no-floppy

mkdir /etc/zfs/zfs-list.cache
touch /etc/zfs/zfs-list.cache/bpool
touch /etc/zfs/zfs-list.cache/rpool
zed -F

echo "Hopefully these aren't empty"
cat /etc/zfs/zfs-list.cache/bpool
cat /etc/zfs/zfs-list.cache/rpool



 
sed -Ei "s|/mnt/?|/|" /etc/zfs/zfs-list.cache/*

zfs snapshot bpool/BOOT/debian@install
zfs snapshot rpool/ROOT/debian@install

exit
