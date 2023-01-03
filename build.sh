#!/bin/bash

PRODUCT=${PRODUCT:-asbru-cm}

if [ -z "$TRAVIS_TAG" ]; then
  eval "$(egrep -o 'APPVERSION.*=.*' lib/PACUtils.pm | tr -d '[:space:]')"
  export VERSION=$APPVERSION~$(date +"%s");
  echo "No Travis Tag set. We are using a timestamp in seconds: ${VERSION}"
else
  export VERSION=$TRAVIS_TAG
  echo "Our version will be the tag ${VERSION}"
fi

cp -r dist/${PACKAGE}/* .

if [ "${SCRIPT}" == "make_debian.sh" ]; then
  mkdir build
  ./make_debian.sh
  cp *.{deb,tar.xz,dsc,build,changes} build/
else
  git clone https://github.com/packpack/packpack.git packpack
  ./packpack/packpack
fi

if [ "${PACKAGE}" == "deb" ] && [ "${REPACK_DEB}" == "yes" ] ; then
  DEBFILE=${PRODUCT}_${VERSION}-1_all.deb
  DEBFILE_OLD=$(basename ${DEBFILE} .deb).deb.old
  echo "Repacking debian file [${DEBFILE}] to have XY format."
  pushd build
  mv ${DEBFILE} ${DEBFILE_OLD}
  dpkg-deb -x ${DEBFILE_OLD} tmp
  dpkg-deb -e ${DEBFILE_OLD} tmp/DEBIAN
  dpkg-deb -b tmp ${DEBFILE}
  rm -rf tmp
  popd
fi

