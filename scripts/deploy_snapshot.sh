#!/bin/bash

for f in build/*.${PACKAGE}
do
	echo "Processing $f"
        cloudsmith push ${PACKAGE} asbru-cm/asbru-cm/${OS}/${DIST} $f
done

if [ $PACKAGE == "deb" ]
then
	cloudsmith push ${PACKAGE} asbru-cm/asbru-cm/${OS}/${DIST} build/*.dsc --sources-file build/*.tar.xz
fi
