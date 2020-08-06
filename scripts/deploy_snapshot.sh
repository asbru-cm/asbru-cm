#!/bin/bash

for f in build/*.{deb,rpm,dsc}
do
	echo "Processing $f"
        cloudsmith push ${PACKAGE} asbru-cm/asbru-cm/${OS}/${DIST} $f
done
