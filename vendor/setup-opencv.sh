#!/usr/bin/env bash
set -euxo pipefail

sudo apt install -y cmake g++ wget unzip
PackageURL="https://github.com/opencv/opencv/archive/4.x.zip"
PackageContribURL="https://github.com/opencv/opencv_contrib/archive/4.x.zip"
TemporaryDirectory=$(mktemp -d)
cd "$TemporaryDirectory"
wget -O opencv.zip $PackageURL
wget -O opencv_contrib.zip $PackageContribURL
unzip opencv.zip
unzip opencv_contrib.zip
mkdir -p build && cd build
cmake -DOPENCV_EXTRA_MODULES_PATH=../opencv_contrib-4.x/modules ../opencv-4.x
cmake --build . -j $(nproc)
sudo make install
cd -
rm -rf "$TemporaryDirectory"
