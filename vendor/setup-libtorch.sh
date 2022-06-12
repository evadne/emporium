#!/usr/bin/env bash
set -euxo pipefail

# Sets up the correct LibTorch variant based on the pre-determined version.

if [ -z ${LIBTORCH_INSTALL_DIR:-} ]; then
  LIBTORCH_INSTALL_DIR="$(dirname $(realpath $0))/libtorch"
fi

if [ -z ${LIBTORCH_VERSION:-} ]; then
  LIBTORCH_VERSION="2.0.0"
fi

if [ "$(uname -s)" = "Linux" ]; then
  if [ -z ${LIBTORCH_TARGET:-} ]; then
    if command -v nvidia-smi >/dev/null 2>&1; then
      LIBTORCH_TARGET="cu118"
    else
      LIBTORCH_TARGET="cpu"
    fi
  fi
  if [ "$LIBTORCH_VERSION" == "nightly" ]; then
    PackageURLPrefix="https://download.pytorch.org/libtorch/nightly/$LIBTORCH_TARGET"
    PackageURL="$PackageURLPrefix/libtorch-cxx11-abi-shared-with-deps-latest.zip"
  else
    PackageURLPrefix="https://download.pytorch.org/libtorch/$LIBTORCH_TARGET"
    PackageURL="$PackageURLPrefix/libtorch-cxx11-abi-shared-with-deps-$LIBTORCH_VERSION%2B$LIBTORCH_TARGET.zip"
  fi
elif [ "$(uname -s)" = "Darwin" ]; then
  LIBTORCH_TARGET="cpu"
  PackageURLPrefix="https://download.pytorch.org/libtorch/$LIBTORCH_TARGET"
  PackageURL="$PackageURLPrefix/libtorch-macos-$LIBTORCH_VERSION.zip"
else
  echo "Unsupported Architecture"
  exit 1;
fi

echo "Downloading: $PackageURL"
mkdir -p $LIBTORCH_INSTALL_DIR

TemporaryDirectory=$(mktemp -d)
cd "$TemporaryDirectory"
wget -q -O libtorch.zip "$PackageURL"
mkdir -p "$LIBTORCH_INSTALL_DIR"
unzip libtorch.zip -d "$TemporaryDirectory"
mv $TemporaryDirectory/libtorch/* "$LIBTORCH_INSTALL_DIR"
rm -rf "$TemporaryDirectory"

# Workaround of https://github.com/pytorch/pytorch/issues/68980#issuecomment-1208054795
# using cu118 / PyTorch 2.0.0

if [ ! -f "$LIBTORCH_INSTALL_DIR/lib/libnvrtc-builtins.so.11.8" ]; then
  if compgen -G "$LIBTORCH_INSTALL_DIR/lib/libnvrtc-builtins-*.so.11.8" > /dev/null; then
    ls -1 $LIBTORCH_INSTALL_DIR/lib/libnvrtc-builtins-*.so.11.8 | \
      xargs -I{} cp {} "$LIBTORCH_INSTALL_DIR/lib/libnvrtc-builtins.so.11.8"
  fi
fi

# Also affected:
# libnvrtc-672ee683.so.11.2
# libnvToolsExt-847d78f2.so.1
