#!/bin/sh

set -e

mkdir ${HOME}/build
cd ${HOME}/build

apt-get download libtinfo5
dpkg -x *.deb ${HOME}/.local/usr


cd ../
rm -rf ${HOME}/build
