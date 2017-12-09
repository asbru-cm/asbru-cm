#!/bin/bash

if [ -z "$TRAVIS_TAG" ]; then
	eval "$(egrep -o 'APPVERSION.*=.*' lib/PACUtils.pm | tr -d '[:space:]')"
	export VERSION=$APPVERSION~$(date +"%s");
	echo "No Travis Tag set. We are using a timestamp in seconds: ${VERSION}"
fi

cp -r dist/${PACKAGE}/* .

if [ "${SCRIPT}" == "make_debian.sh" ]; then
	mkdir build
	./make_debian.sh
	cp *.{deb,tar.xz,dsc,build,changes} build/
else
	git clone https://github.com/packpack/packpack.git packpack
	sudo ./packpack/packpack
fi
