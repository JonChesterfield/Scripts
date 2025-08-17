#!/bin/bash

set -e
set -x
set -o pipefail

id=`id -u`
if [ $id = "0" ]
then
    echo "Meant to run as user"
    exit 1
else
    echo "Running as user"
fi

gsettings set org.gnome.desktop.media-handling automount false

