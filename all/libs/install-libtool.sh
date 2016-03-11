#!/usr/bin/env zsh

source ${HOME}/.aliases
set -e

mkdir -p ${HOME}/build
cd ${HOME}/build

wget http://ftpmirror.gnu.org/libtool/libtool-2.4.6.tar.gz
tar xf libtool-2.4.6.tar.gz

cd libtool-2.4.6
./configure \
    CFLAGS='-fPIC' \
    --prefix=$HOME/.local/usr

make CFLAGS='-fPIC' -j
make install

cd ../..

rm ${HOME}/build -rf
