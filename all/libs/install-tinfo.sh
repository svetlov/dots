#!/usr/bin/env zsh

source ${HOME}/.aliases
set -e

mkdir -p ${HOME}/build
cd ${HOME}/build

apt-get download libtinfo5
dpkg -x *.deb ${HOME}/.local
ln -s ~/.local/lib/x86_64-linux-gnu/libtinfo.so.5 ~/.local/lib/x86_64-linux-gnu/libtinfo.so

cd ../
rm -rf ${HOME}/build
