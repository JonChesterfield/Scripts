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
    echo "Check arguments, expected username"
    exit 1
fi


USERNAME=$1

zfs create rpool/home/$USERNAME
adduser $USERNAME

cp -a /etc/skel/. /home/$USERNAME
chown -R $USERNAME:$USERNAME /home/$USERNAME
usermod -a -G audio,cdrom,dip,floppy,netdev,plugdev,sudo,video,render $USERNAME


# Fair chance of running out of memory and got a lot of disk, give it a chance
# to survive that
zfs create -V 16G -b $(getconf PAGESIZE) -o compression=zle \
    -o logbias=throughput -o sync=always \
    -o primarycache=metadata -o secondarycache=none \
    -o com.sun:auto-snapshot=false rpool/swap

mkswap -f /dev/zvol/rpool/swap
echo /dev/zvol/rpool/swap none swap discard 0 0 >> /etc/fstab
echo RESUME=none > /etc/initramfs-tools/conf.d/resume

swapon -av

