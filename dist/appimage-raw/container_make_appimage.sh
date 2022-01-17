#!/bin/bash

# This file should be ran from the project's root directory as cwd.

# http://redsymbol.net/articles/unofficial-bash-strict-mode/ ;)
set -euo pipefail
IFS=$'\n\t'

# Too much output can't hurt, it's Bash.
set -x

ln -s /var/appimage-dir/opt/asbru-cm/res/asbru-cm.desktop /var/appimage-dir/asbru-cm.desktop
ln -s /var/appimage-dir/opt/asbru-cm/res/asbru-logo.svg /var/appimage-dir/asbru-cm.svg
ln -s /var/appimage-dir/opt/asbru-cm/res/asbru-logo-256.png /var/appimage-dir/.DirIcon
ln -s /var/appimage-dir/opt/asbru-cm/dist/appimage-raw/AppRun /var/appimage-dir/AppRun

mkdir -p /var/appimage-dir/usr/share/metainfo/

ln -s /var/appimage-dir/opt/asbru-cm/res/org.asbru.cm.appdata.xml /var/appimage-dir/usr/share/metainfo/org.asbru.cm.appdata.xml

LD_LIBRARY_PATH="/usr/glibc-compat/lib64:/usr/glibc-compat/lib:/usr/lib:/usr/local/lib:/usr/local/share:/lib" ./appimagetool-x86_64.AppImage /var/appimage-dir Asbru-CM.AppImage

