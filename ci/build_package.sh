#!/usr/bin/env bash
set -euo pipefail

PRODUCT=${PRODUCT:-asbru-cm}

if [ "${GITHUB_REF_TYPE:-}" = "tag" ] && [ -n "${GITHUB_REF_NAME:-}" ]; then
  RAW_TAG="${GITHUB_REF_NAME}"
  VERSION="${RAW_TAG#v}"
  CHANNEL="release"
  echo "Detected tag build. VERSION=${VERSION}, CHANNEL=${CHANNEL}"
else
  eval "$(egrep -o 'APPVERSION.*=.*' lib/PACUtils.pm | tr -d '[:space:]')"
  SHORT_SHA="$(git rev-parse --short HEAD)"
  BRANCH_NAME="${GITHUB_REF_NAME:-unknown}"
  VERSION="${APPVERSION}+${BRANCH_NAME}.${SHORT_SHA}"
  CHANNEL="${BRANCH_NAME}"
  echo "Detected branch build. VERSION=${VERSION}, CHANNEL=${CHANNEL}"
fi

export VERSION CHANNEL

echo "PACKAGE=${PACKAGE:-unset}, OS=${OS:-unset}, DIST=${DIST:-unset}"

cp -r "dist/${PACKAGE}/"* .

mkdir -p build

if [ "${PACKAGE}" = "deb" ]; then
  echo "Building Debian package for ${OS}/${DIST}..."
  git clone https://github.com/packpack/packpack.git packpack
  ./packpack/packpack
elif [ "${PACKAGE}" = "rpm" ]; then
  echo "Building RPM package for ${OS}/${DIST}..."
  git clone https://github.com/packpack/packpack.git packpack
  ./packpack/packpack
else
  echo "Unknown PACKAGE=${PACKAGE}. Expected 'deb' or 'rpm'."
  exit 1
fi

echo "Build done. Artifacts in ./build:"
ls -la build || true
