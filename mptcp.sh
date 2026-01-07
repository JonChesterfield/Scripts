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

if [ "$#" -ne 1 ]; then
    echo "Check arguments, expected disk to install to"
    exit 1
fi

DISK=$1


apt update -y
apt install -y wget


VER=openmptcprouter-v0.63-6.12-r0+30806-070d8eb4d5-x86-64-generic

wget https://releases.openmptcprouter.com/v0.63-6.12/x86_64/targets/x86/64/$VER-ext4-combined-efi.img.gz

echo 'a61c1ba9e4a2993955b28ffeb26adf95e435189c330da7108d1ea845b464ea66 $VER-ext4-combined-efi.img.gz' > $VER-ext4-combined-efi.img.gz.sha256sum

sha256sum -c $VER-ext4-combined-efi.img.gz.sha256sum

gzip -d $VER-ext4-combined-efi.img.gz

dd if=/$VER-ext4-combined-efi.img of=$DISK bs=4k
sync


apt install -y gparted
gparted # todo, parted

exit 0
