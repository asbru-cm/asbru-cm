#!/bin/bash

# This file should be ran from the project's root directory as cwd.

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# http://redsymbol.net/articles/unofficial-bash-strict-mode/ ;)
set -euo pipefail
IFS=$'\n\t'

# Too much output can't hurt, it's Bash.
set -x

docker build --tag=asbru-cm-appimage-maker --file=dist/appimage-raw/Dockerfile .

mkdir -p "${SCRIPT_DIR}/build"

CIDFILE_PATH="${SCRIPT_DIR}/build/appimage-maker.cid"

rm -f "${CIDFILE_PATH}"

docker run --cidfile "${CIDFILE_PATH}" --privileged=true -i asbru-cm-appimage-maker //bin/bash < "${SCRIPT_DIR}/container_make_appimage.sh"

CONTAINER_ID="$(cat "${CIDFILE_PATH}")"
rm -f "${CIDFILE_PATH}"

APPIMAGE_DESTINATION="${SCRIPT_DIR}/build/Asbru-CM.AppImage"

rm -f "${APPIMAGE_DESTINATION}"
docker cp "${CONTAINER_ID}:/Asbru-CM.AppImage" "${APPIMAGE_DESTINATION}"

docker rm "${CONTAINER_ID}"

chmod a+x "${APPIMAGE_DESTINATION}"
