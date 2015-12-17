#!/usr/bin/env zsh

set -e

source ${HOME}/.aliases

mkdir -p ${HOME}/build
cd ${HOME}/build

wget http://sourceforge.net/projects/levent/files/libevent/libevent-1.4/libevent-1.4.15.tar.gz/download
tar xvzf download

cd libevent-1.4.15
./configure CFLAGS='-fPIC' --prefix=$HOME/.local/usr
make CFLAGS='-fPIC' -j
make install

cd ../..

rm ${HOME}/build -r
