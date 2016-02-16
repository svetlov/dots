#!/usr/bin/env zsh

set -e

source ${HOME}/.aliases

mkdir -p ${HOME}/build
cd ${HOME}/build

wget --no-check-certificate https://cmake.org/files/v3.4/cmake-3.4.1.tar.gz
tar zxf cmake-3.4.1.tar.gz

cd cmake-3.4.1

./bootstrap --prefix=${HOME}/.local
make -j
make install

cd ../..

rm ${HOME}/build -rf
