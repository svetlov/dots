#!/usr/bin/env zsh

source ${HOME}/.aliases

set -e

VERSION="3.8.0"

mkdir -p ${HOME}/build
cd ${HOME}/build

wget http://llvm.org/releases/${VERSION}/clang+llvm-${VERSION}-x86_64-linux-gnu-ubuntu-14.04.tar.xz
tar xvfJ clang+llvm-${VERSION}-x86_64-linux-gnu-ubuntu-14.04.tar.xz

cp clang+llvm-${VERSION}-x86_64-linux-gnu-ubuntu-14.04/* $HOME/.local/usr/ -r

cd ../..

rm ${HOME}/build -rf
