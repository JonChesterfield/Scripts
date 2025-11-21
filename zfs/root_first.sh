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


if [ "$#" -ne 3 ]; then
    echo "Check arguments, expected hostname disk iface"
    ls /dev/disk/by-id
    exit 1
fi

HOSTNAME=$1
DISK=$2
IFACE=$3


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

sync
sleep 3

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
    -O encryption=on -O keylocation=prompt -O keyformat=passphrase \
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

# Reasonable on single disk systems
zfs set copies=2 bpool
zfs set copies=2 rpool

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

# Ideally it would start running this script automatically
cp in_chroot.sh /mnt/tmp/in_chroot.sh

mount --make-private --rbind /dev  /mnt/dev
mount --make-private --rbind /proc /mnt/proc
mount --make-private --rbind /sys  /mnt/sys
echo "Continuation is in /tmp/in_chroot.sh"
chroot /mnt /usr/bin/env DISK=$DISK bash --login


mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | \
    xargs -i{} umount -lf {}

sleep 5

zpool export -a

echo "Hopefully not busy"



