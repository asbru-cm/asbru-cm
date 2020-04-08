#!/bin/bash

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
	sudo ./packpack/packpack
	if [ "$PACKAGE" == "deb" ]; then
		echo $1 > gpg_passphrase.txt
		dpkg-sig --gpg-options '--passphrase-file gpg_passphrase.txt --batch --no-use-agent' --sign origin -k DAF15319138C6A8F build/*.deb
		debsign -p'gpg --passphrase-file gpg_passphrase.txt --batch --no-use-agent' -k DAF15319138C6A8F build/*.dsc
		rm gpg_passphrase.txt
	fi
fi