#!/bin/bash

set -e
set -x
set -o pipefail

HOSTNAME=milan

id=`id -u`
if [ $id = "0" ]
then
    echo "Running as root"
else
    echo "Meant to run as root"
    exit 1
fi


if [ "$#" -ne 2 ]; then
    echo "Check arguments, expected $disk iface"
    ls /dev/disk/by-id
    exit 1
fi

DISK=$1
IFACE=$2


if [[ -e "$DISK" ]]
then
    echo "$DISK exists, going to run with that"
else
    echo "Disk $DISK doesn't look right"
    exit 1
fi


cat << "EOF" > /etc/apt/sources.list
deb http://deb.debian.org/debian/ trixie main contrib non-free-firmware
deb-src http://deb.debian.org/debian/ trixie main contrib non-free-firmware
EOF

apt update --yes
apt install --yes openssh-server
systemctl restart ssh

apt install --yes linux-headers-$(uname -r)
apt install --yes dkms
apt install --yes debootstrap gdisk

apt install --yes zfsutils-linux



swapoff --all

echo "Destroying existing disk layout"
wipefs -a $DISK
blkdiscard -f $DISK
sgdisk --zap-all $DISK
partprobe $DISK

echo "UEFI time"
sgdisk     -n2:1M:+512M   -t2:EF00 $DISK
sgdisk     -n3:0:+1G      -t3:BF01 $DISK
sgdisk     -n4:0:0        -t4:BF00 $DISK

zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -o compatibility=grub2 \
    -o cachefile=/etc/zfs/zpool.cache \
    -O devices=off \
    -O acltype=posixacl -O xattr=sa \
    -O compression=lz4 \
    -O normalization=formD \
    -O relatime=on \
    -O canmount=off -O mountpoint=/boot -R /mnt \
    bpool ${DISK}-part3

zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl -O xattr=sa -O dnodesize=auto \
    -O compression=lz4 \
    -O normalization=formD \
    -O relatime=on \
    -O canmount=off -O mountpoint=/ -R /mnt \
    rpool ${DISK}-part4


zfs create -o canmount=off -o mountpoint=none rpool/ROOT
zfs create -o canmount=off -o mountpoint=none bpool/BOOT

zfs create -o canmount=noauto -o mountpoint=/ rpool/ROOT/debian
zfs mount rpool/ROOT/debian
zfs create -o mountpoint=/boot bpool/BOOT/debian

zfs create                     rpool/home
zfs create -o mountpoint=/root rpool/home/root
chmod 700 /mnt/root

# Have a tmpfs
mkdir /mnt/run
mount -t tmpfs tmpfs /mnt/run
mkdir /mnt/run/lock

debootstrap trixie /mnt

mkdir /mnt/etc/zfs
cp /etc/zfs/zpool.cache /mnt/etc/zfs/

hostname $HOSTNAME
hostname > /mnt/etc/hostname

# A hack, but whatever
echo "127.0.1.1 $HOSTNAME" >> /mnt/etc/hosts





cat << EOF > /mnt/etc/network/interfaces.d/$IFACE
auto $IFACE
iface $IFACE inet dhcp
EOF


cat << EOF > /mnt/etc/apt/sources.list
deb http://deb.debian.org/debian trixie main contrib non-free-firmware
deb-src http://deb.debian.org/debian trixie main contrib non-free-firmware

deb http://deb.debian.org/debian-security trixie-security main contrib non-free-firmware
deb-src http://deb.debian.org/debian-security trixie-security main contrib non-free-firmware

deb http://deb.debian.org/debian trixie-updates main contrib non-free-firmware
deb-src http://deb.debian.org/debian trixie-updates main contrib non-free-firmware
EOF

mount --make-private --rbind /dev  /mnt/dev
mount --make-private --rbind /proc /mnt/proc
mount --make-private --rbind /sys  /mnt/sys
chroot /mnt /usr/bin/env DISK=$DISK bash --login

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


apt install --yes openssh-server

# temporary
sed -i sed 's$#PermitRootLogin prohibit-password$PermitRootLogin yes # todo, undo this...$g' /etc/ssh/sshd_config

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

mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | \
    xargs -i{} umount -lf {}

sleep 5

zpool export -a

echo "Hopefully not busy"



