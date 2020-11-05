#!/bin/bash

readonly DEST="${1:-snapshots}"

main() {
  local var
  local file

  for var in PACKAGE OS DIST
  do
    if [ -z ${!var} ]
    then
      echo "ERROR: environment variable [${var}] must be set."
      exit 1
    fi
  done

  for file in build/*.${PACKAGE}
  do
    echo "Pushing $file to cloudsmith..."
    cloudsmith push ${PACKAGE} asbru-cm/${DEST}/${OS}/${DIST} $file
  done

  if [ $PACKAGE == "deb" ]
  then
    echo "Pushing DSC files to cloudsmith..."
    cloudsmith push ${PACKAGE} asbru-cm/${DEST}/${OS}/${DIST} build/*.dsc --sources-file build/*.debian.tar.xz
  fi
}
main
