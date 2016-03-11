#!/usr/bin/env zsh

source ${HOME}/.aliases
set -e

mkdir -p ${HOME}/build
cd ${HOME}/build

wget https://sourceforge.net/projects/freetype/files/freetype2/2.6.3/freetype-2.6.3.tar.bz2/download#
mv download freetype-2.6.3.tar.bz2

tar xf freetype-2.6.3.tar.bz2

cd freetype-2.6.3

./configure --prefix=${HOME}/.local
make -j
make install

cd ../..

rm -rf ${HOME}/build
