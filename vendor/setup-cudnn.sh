#!/usr/bin/env bash
set -euxo pipefail

# check https://developer.download.nvidia.com/compute/redist/cudnn/v8.8.0/local_installers/12.0/
CUDNN_PATH="$(dirname $(realpath $0))/cache/cudnn-linux-x86_64-8.4.1.50_cuda11.6-archive.tar.xz"

TemporaryDirectory=$(mktemp -d)
cd $TemporaryDirectory
tar -xzf $CUDNN_PATH -C . --strip-components=1
cp include/cudnn*.h /usr/local/cuda/include
cp -P lib/libcudnn* /usr/local/cuda/lib64 
chmod a+r /usr/local/cuda/include/cudnn*.h /usr/local/cuda/lib64/libcudnn*
rm -rf "$TemporaryDirectory"
