#!/bin/bash

mkdir -p build/linux_debug

(
  cd ./sauce/sokol/ || exit 1
  if [ ! -e ./app/sokol_app_linux_x64_gl_debug.a ]; then
    echo "Building sokol..."
    bash build_clibs_linux.sh
  fi
)

odin run ./sauce/build -- target:linux
