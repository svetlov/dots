#!/usr/bin/env zsh

source ${HOME}/.aliases
set -e

mkdir -p ${HOME}/build
cd ${HOME}/build

wget https://pkg-config.freedesktop.org/releases/pkg-config-0.29.tar.gz

tar xf pkg-config-0.29.tar.gz

cd pkg-config-0.29

./configure --prefix=${HOME}/.local --with-internal-glib
make -j
make install

cd ../..

rm -rf ${HOME}/build
