#!/bin/sh
# Builds tronb2 against Tom Seddon's b2 (https://github.com/tom-seddon/b2) in
# $B2SRC (default ~/b2src/b2, cloned at the commit below if absent), in its own
# build directory, $B2SRC/build/r.tron.  b2 itself is not changed.
set -e
B2COMMIT=2cd8e53a8ab3c366f8b0c015770f724fe49d8533
B2SRC=${B2SRC:-$HOME/b2src/b2}
HERE=$(cd "$(dirname "$0")" && pwd)
if [ ! -d "$B2SRC/.git" ]; then
  git clone --recursive https://github.com/tom-seddon/b2.git "$B2SRC"
  ( cd "$B2SRC" && git checkout -q $B2COMMIT && git submodule update --init --recursive -q )
fi
OUT="$B2SRC/build/r.tron"
mkdir -p "$OUT"
if [ ! -f "$OUT/build.ninja" ]; then
  ( cd "$OUT" && cmake -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion 2>/dev/null || echo 12.0) \
      -DCMAKE_OSX_SYSROOT=macosx \
      -DCMAKE_PROJECT_b2_INCLUDE="$HERE/tronb2.cmake" ../.. > cmake.log )
fi
ninja -C "$OUT" tronb2
echo "built $OUT/tronb2"
