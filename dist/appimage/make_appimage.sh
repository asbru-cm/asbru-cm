#!/bin/bash

###############################################################################
# This file is part of Ásbrú Connection Manager
#
# Copyright (C) 2017-2021 Ásbrú Connection Manager team (https://asbru-cm.net)
#
# Ásbrú Connection Manager is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ásbrú Connection Manager is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License version 3
# along with Ásbrú Connection Manager.
# If not, see <http://www.gnu.org/licenses/gpl-3.0.html>.
###############################################################################

###############################################################################
# Creates AppImage release of Ásbrú Connection Manager
###############################################################################

# Requirements:
#  - cloudsmith-cli (https://github.com/cloudsmith-io/cloudsmith-cli)
#  - appimage-builder (https://github.com/AppImageCrafters/appimage-builder)
#  - jq (https://stedolan.github.io/jq/)

# References:
#  - https://help.cloudsmith.io/docs/cli-scripting
#  - https://docs.appimage.org/
#  - https://appimage-builder.readthedocs.io/en/latest/reference/version_1.html

readonly ASBRU_RELEASE="${1:-release}"
readonly UBUNTU_RELEASE="${2:-bionic}"
readonly APPDIR="./AppDir"

main() {
  local ASBRU_VERSION=$(cloudsmith ls pkgs asbru-cm/${ASBRU_RELEASE} -q "distribution:ubuntu/${UBUNTU_RELEASE} filename:.deb\$" -F pretty_json | jq -r '.data[0].version_orig')
  if [ -z "${ASBRU_VERSION}" ]; then
    echo "ERROR: Unable to retrieve the latest Ásbrú version on cloudsmith for release ubuntu/${UBUNTU_RELEASE}, build aborted."
    exit 1;
  fi

  local CLOUDSMITH_KEY=$(cloudsmith repos ls asbru-cm/${ASBRU_RELEASE} -F pretty_json | jq -r '.data[0].gpg_keys[0].fingerprint_short')
  if [ -z "${CLOUDSMITH_KEY}" ]; then
    echo "ERROR: Unable to retrieve cloudsmith repository key for asbru-cm/${ASBRU_RELEASE}, build aborted."
    exit 2;
  fi

  local DEST_FILENAME="asbru-cm-${ASBRU_VERSION}-x86_64.AppImage"
  if [ -r "${DEST_FILENAME}" ]; then
    echo "WARNING: Destination filename [${DEST_FILENAME}] already exists and will be replaced."
  fi

  echo "INFO: Preparting AppDir [${APPDIR}]..."
  if [ ! -d "${DEST_FILENAME}" ]; then
    mkdir -p ${APPDIR}
  fi
  if [ ! -d "${APPDIR}" ]; then
    echo "ERROR: Unable to create AppDir [${APPDIR}], build aborted."
    exit 3
  fi

  echo "INFO: Building AppImage directory ${ASBRU_VERSION}, be patient ..."
  env UBUNTU_RELEASE=${UBUNTU_RELEASE}  \
      ASBRU_RELEASE=${ASBRU_RELEASE}    \
      ASBRU_VERSION=${ASBRU_VERSION}    \
      CLOUDSMITH_KEY=${CLOUDSMITH_KEY}  \
    appimage-builder --skip-script --skip-tests --skip-appimage --recipe asbru-cm-appimage.yml

  echo "INFO: Prepare desktop and icon files..."
  cp -f ${APPDIR}/usr/share/applications/asbru-cm.desktop ${APPDIR}/
  cp -f ${APPDIR}/opt/asbru/res/asbru-logo.svg ${APPDIR}/asbru-cm.svg
  cp -f ${APPDIR}/opt/asbru/res/asbru-logo.svg ${APPDIR}/.DirIcon
  if [ -f ${APPDIR}/opt/share/res/asbru-cm.appdata.xml ] && [ !f ${APPDIR}/usr/share/metainfo/asbru-cm.appdata.xml ]; then
    cp -f ${APPDIR}/opt/share/res/asbru-cm.appdata.xml ${APPDIR}/usr/share/metainfo/
  fi
  rm -f ${APPDIR}/utilities-terminal.svg

  echo "INFO: Generate AppImage release ${ASBRU_VERSION}, be patient ..."
  env UBUNTU_RELEASE=${UBUNTU_RELEASE}  \
      ASBRU_RELEASE=${ASBRU_RELEASE}    \
      ASBRU_VERSION=${ASBRU_VERSION}    \
      CLOUDSMITH_KEY=${CLOUDSMITH_KEY}  \
    appimage-builder --skip-script --skip-build --skip-tests --recipe asbru-cm-appimage.yml

  if [ ! -r "${DEST_FILENAME}" ]; then
    echo "ERROR: Destination filename [${DEST_FILENAME}] has not be built correctly."
    exit 4
  else
    echo "SUCCESS: Destination filename [${DEST_FILENAME}] has been built correctly."
  fi

  echo "All done. Hopefully :)"
}
main
