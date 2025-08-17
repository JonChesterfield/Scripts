#!/bin/bash

set -e
set -x
set -o pipefail

OUTDIR=/home/jon/Scripts/zfs

id=`id -u`
if [ $id = "0" ]
then
    echo "Running as root"
else
    echo "Meant to run as root"
    exit 1
fi


if [ "$#" -ne 1 ]; then
    echo "Check arguments, expected $disk"
    ls /dev/disk/by-id
    exit 1
fi

DISK=$1

if [[ -e "$DISK" ]]
then
    echo "$DISK exists, going to run with that"
else
    echo "Disk $DISK doesn't look right"
    exit 1
fi


mkdir -p $OUTDIR/etc/apt
cat << "EOF" > $OUTDIR/etc/apt/sources.list
deb http://deb.debian.org/debian/ trixie main contrib non-free-firmware
deb-src http://deb.debian.org/debian/ trixie main contrib non-free-firmware
EOF

apt update --yes
apt install --yes openssh-server
systemctl restart ssh

apt install --yes linux-headers-$(uname-r)
apt install --yes dkms
apt install --yes debootstrap gdisk


