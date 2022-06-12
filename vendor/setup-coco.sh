#!/usr/bin/env bash
set -euxo pipefail

if [ -z ${COCO_INSTALL_DIR:-} ]; then
  COCO_INSTALL_DIR="$(dirname $(realpath $0))/dataset/coco"
fi

if [ -z ${COCO_TYPE:-} ]; then
  COCO_TYPE="val2017"
fi

PackageURL="http://images.cocodataset.org/zips/$COCO_TYPE.zip"
echo "Downloading: $PackageURL"
mkdir -p $COCO_INSTALL_DIR

TemporaryDirectory=$(mktemp -d)
mkdir -p "$TemporaryDirectory/install"
cd "$TemporaryDirectory"
wget -q -O package.zip $PackageURL
unzip package.zip -d "$TemporaryDirectory/install"
mkdir -p "$COCO_INSTALL_DIR"
mv $TemporaryDirectory/install/* "$COCO_INSTALL_DIR"
rm -rf "$TemporaryDirectory"
