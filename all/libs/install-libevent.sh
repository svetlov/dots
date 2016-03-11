#!/usr/bin/env zsh

source ${HOME}/.aliases
set -e

mkdir -p ${HOME}/build
cd ${HOME}/build

wget https://github.com/libevent/libevent/archive/release-1.4.15-stable.tar.gz
tar xf release-1.4.15-stable.tar.gz

cd libevent-release-1.4.15-stable
./autogen.sh
./configure CFLAGS='-fPIC' --prefix=$HOME/.local/usr
make CFLAGS='-fPIC' -j
make install

cd ../..

rm ${HOME}/build -rf
