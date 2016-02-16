#!/usr/bin/env zsh

set -e

source ${HOME}/.aliases

mkdir -p ${HOME}/build
cd ${HOME}/build

git clone git://source.ffmpeg.org/ffmpeg.git ffmpeg
cd ffmpeg

./configure --prefix=$HOME/.local --disable-yasm --enable-pic --extra-ldexeflags=-pie
make -j
make install

cd ../..
rm ${HOME}/build -rf
