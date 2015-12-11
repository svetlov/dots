#!/bin/sh

set -e

mkdir ${HOME}/build
cd ${HOME}/build

wget http://llvm.org/releases/3.7.0/clang+llvm-3.7.0-x86_64-linux-gnu-ubuntu-14.04.tar.xz
tar xvfJ clang+llvm-3.7.0-x86_64-linux-gnu-ubuntu-14.04.tar.xz

cp clang+llvm-3.7.0-x86_64-linux-gnu-ubuntu-14.04/* $HOME/.local/usr/ -r

cd ../..

rm ${HOME}/build -r
