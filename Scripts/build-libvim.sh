#!/bin/sh

set -eu

LIBVIM_COMMIT="9ade7d1e2ac54cb945724762cb8be9c68adef3f0"
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

git clone --quiet https://github.com/onivim/libvim.git "$WORK_DIR/libvim"
git -C "$WORK_DIR/libvim" checkout --quiet "$LIBVIM_COMMIT"

cd "$WORK_DIR/libvim/src"
./configure --disable-selinux \
    CFLAGS="-mmacosx-version-min=26.0 -Wno-implicit-int -Wno-implicit-function-declaration -Wno-unused-but-set-variable -Wno-implicit-const-int-float-conversion"
make -j"$(sysctl -n hw.ncpu)" libvim.a \
    WARN_FLAGS="-Wall -Wno-array-bounds -Wno-unknown-warning-option -Wno-cpp -Wno-pointer-sign -Wno-unused-parameter -Wno-strict-overflow -Wno-return-type -Wno-unused-but-set-variable -Wno-implicit-const-int-float-conversion"

cp libvim.a "$PROJECT_DIR/Vendor/LibVim/lib/libvim.a"
