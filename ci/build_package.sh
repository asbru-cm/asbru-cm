#!/usr/bin/env bash
set -euo pipefail

PRODUCT=${PRODUCT:-asbru-cm}

if [ "${GITHUB_REF_TYPE:-}" = "tag" ] && [ -n "${GITHUB_REF_NAME:-}" ]; then
  RAW_TAG="${GITHUB_REF_NAME}"
  RAW_VERSION="${RAW_TAG#v}"
  CHANNEL="release"
  echo "Detected tag build. RAW_VERSION=${RAW_VERSION}, CHANNEL=${CHANNEL}"
else
  eval "$(egrep -o 'APPVERSION.*=.*' lib/PACUtils.pm | tr -d '[:space:]')"
  SHORT_SHA="$(git rev-parse --short HEAD)"
  BRANCH_NAME="${GITHUB_REF_NAME:-build}"
  RAW_VERSION="${APPVERSION}+${BRANCH_NAME}.${SHORT_SHA}"
  CHANNEL="${BRANCH_NAME}"
  echo "Detected branch build. RAW_VERSION=${RAW_VERSION}, CHANNEL=${CHANNEL}"
fi

SAFE_VERSION="$(printf '%s' "${RAW_VERSION}" | tr '[:upper:]' '[:lower:]')"
SAFE_VERSION="$(printf '%s' "${SAFE_VERSION}" | tr '-' '.')"
SAFE_VERSION="$(printf '%s' "${SAFE_VERSION}" | sed 's/[^0-9a-z.+~]/./g')"

export VERSION="${SAFE_VERSION}"

echo "Final VERSION (for packaging): ${VERSION}"
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


if [ "${PACKAGE}" = "deb" ] && [ "${REPACK_DEB:-}" = "yes" ] ; then
  DEBFILE="${PRODUCT}_${VERSION}-1_all.deb"
  DEBFILE_OLD="$(basename "${DEBFILE}" .deb).deb.old"

  echo "Repacking debian file [${DEBFILE}] to have XY format."

  pushd build >/dev/null

  if [ ! -f "${DEBFILE}" ]; then
    echo "Expected deb file ${DEBFILE} not found in ./build. Available files:"
    ls -la
    popd >/dev/null
    exit 1
  fi

  mv "${DEBFILE}" "${DEBFILE_OLD}"
  dpkg-deb -x "${DEBFILE_OLD}" tmp
  dpkg-deb -e "${DEBFILE_OLD}" tmp/DEBIAN
  dpkg-deb -b tmp "${DEBFILE}"
  rm -rf tmp

  popd >/dev/null
fi

echo "Build done. Artifacts in ./build:"
ls -la build || true
