#!/bin/sh

set -e

mkdir ${HOME}/build
cd ${HOME}/build

apt-get download libtinfo5
dpkg -x *.deb ${HOME}/.local/usr
ln -s ~/.local/usr/lib/x86_64-linux-gnu/libtinfo.so.5 ~/.local/usr/lib/x86_64-linux-gnu/libtinfo.so


cd ../
rm -rf ${HOME}/build
