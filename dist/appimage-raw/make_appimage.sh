#!/bin/bash

# This file should be ran from the project's root directory as cwd.

# http://redsymbol.net/articles/unofficial-bash-strict-mode/ ;)
set -euo pipefail
IFS=$'\n\t'

# Too much output can't hurt, it's Bash.
set -x

docker build --tag=asbru-cm-appimage-maker --file=dist/appimage-raw/Dockerfile .
docker run --privileged=true -it asbru-cm-appimage-maker //bin/bash < container_make_appimage.sh
