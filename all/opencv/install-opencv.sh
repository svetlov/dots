#!/usr/bin/env zsh

set -e

source ${HOME}/.aliases

mkdir -p ${HOME}/build
cd ${HOME}/build

git clone https://github.com/Itseez/opencv.git
cd opencv
git checkout 3.1.0

wget https://raw.githubusercontent.com/Itseez/opencv_3rdparty/81a676001ca8075ada498583e4166079e5744668/ippicv/ippicv_linux_20151201.tgz
mkdir -p 3rdparty/ippicv/downloads/linux-808b791a6eac9ed78d32a7666804320e
mv ippicv_linux_20151201.tgz 3rdparty/ippicv/downloads/linux-808b791a6eac9ed78d32a7666804320e

mkdir build
cd build

cmake -D CMAKE_BUILD_TYPE=Release -D CMAKE_INSTALL_PREFIX=${HOME}/.local -D CMAKE_SHARED_LINKER_FLAGS=-Wl,-Bsymbolic ..
make -j
make install

cd ../..
rm ${HOME}/build -rf
