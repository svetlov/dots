#!/bin/sh

set -e

mkdir -p ${HOME}/build
cd ${HOME}/build

wget https://acelnmp.googlecode.com/files/libevent-2.0.19-stable.tar.gz
tar xvzf libevent-2.0.19-stable.tar.gz

cd libevent-2.0.19-stable
./configure CFLAGS='-fPIC' --prefix=$HOME/.local/usr --disable-shared
make CFLAGS='-fPIC' -j
make install

cd ../..

rm ${HOME}/build -r
