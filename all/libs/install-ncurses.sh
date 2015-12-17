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


ln -s ${HOME}/.local/usr/include/ncursesw/ncurses.h ${HOME}/.local/usr/include/ncurses.h
ln -s ${HOME}/.local/usr/lib/libncursesw.so ${HOME}/.local/usr/lib/libncurses.so

cd ../..

rm ${HOME}/build -rf
