#!/usr/bin/env zsh

set -e

source ${HOME}/.aliases

mkdir -p ${HOME}/build
cd ${HOME}/build

wget https://sourceforge.net/projects/freetype/files/freetype2/2.6.3/freetype-2.6.3.tar.bz2/download#

tar xf freetype-2.6.3.tar.bz2

cd freetype-2.6.3.tar.bz2

./configure --prefix=${HOME}/.local
make -j
make install

cd ../..

rm -rf ${HOME}/build
