#!/bin/bash

if [ -z "$TRAVIS_TAG" ]; then
	eval "$(egrep -o 'APPVERSION.*=.*' lib/PACUtils.pm | tr -d '[:space:]')"
	RELEASE_DEBIAN=$APPVERSION~$(git log -1 | grep -i "^commit" | awk '{print $2}');
	echo "No Travis Tag set. We are guessing a version number from the git log: ${RELEASE_DEBIAN}"
else
	RELEASE_DEBIAN=${TRAVIS_TAG,,};
	echo "Setting version to ${RELEASE_DEBIAN}"
fi

PACKAGE_DIR=build
DEBIAN_VERSION=${RELEASE_DEBIAN/-/"~"}

echo "Building package release ${DEBIAN_VERSION}, be patient ..."

pwd

if ! [[ -z "$TRAVIS_TAG" ]]; then
	git checkout tags/${TRAVIS_TAG}
fi

mkdir $PACKAGE_DIR

tar -cpf "${PACKAGE_DIR}/asbru-cm_$DEBIAN_VERSION.orig.tar" --exclude ".git" --exclude "debian" --exclude "build" .
cp -r debian build/
cd ${PACKAGE_DIR}
tar -xf asbru-cm_$DEBIAN_VERSION.orig.tar
xz -9 asbru-cm_$DEBIAN_VERSION.orig.tar
mv asbru-cm_$DEBIAN_VERSION.orig.tar.xz ../

#ls -lha

if ! [[ -z "$TRAVIS_TAG" ]]; then
	dch -v "$DEBIAN_VERSION" -D "unstable" -b -m "New automatic GitHub build from snapshot"
else
	dch -v "$DEBIAN_VERSION" -D "stable" -b -m "New automatic GitHub build from tag"
fi


debuild -us -uc

#ls -lha
cd ..
#ls -lha

echo "All done. Hopefully"                   
