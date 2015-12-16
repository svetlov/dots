#!/bin/sh

mkdir -p ${HOME}/build
cd ${HOME}/build

wget http://ftp.gnu.org/gnu/ncurses/ncurses-5.9.tar.gz
tar xvzf ncurses-5.9.tar.gz

cd ncurses-5.9
./configure \
    CFLAGS='-fPIC' \
    --prefix=$HOME/.local/usr \
    --with-shared \
    --enable-widec --with-terminfo-dirs=${HOME}/.local/usr/share/terminfo

make CFLAGS='-fPIC' -j
make install

cd ../..

rm ${HOME}/build -r
