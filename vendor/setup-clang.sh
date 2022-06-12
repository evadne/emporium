#!/usr/bin/env bash
set -euxo pipefail

sudo apt-get install \
  clang-format \
  clang-tidy \
  clang-tools \
  clang \
  clangd \
  libc++-dev \
  libc++1 \
  libc++abi-dev \
  libc++abi1 \
  libclang-dev \
  libclang1 \
  liblldb-dev \
  libllvm-ocaml-dev \
  libomp-dev \
  libomp5 \
  lld \
  lldb \
  llvm-dev \
  llvm-runtime \
  llvm
