#!/usr/bin/env zsh

source ${HOME}/.aliases
set -e

mkdir -p ${HOME}/build
cd ${HOME}/build

wget http://ftp.gnu.org/gnu/automake/automake-1.15.tar.gz
tar xf automake-1.15.tar.gz

cd automake-1.15
./configure \
    CFLAGS='-fPIC' \
    --prefix=$HOME/.local/usr

make CFLAGS='-fPIC' -j
make install

cd ../..

rm ${HOME}/build -rf
