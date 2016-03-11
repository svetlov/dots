#!/usr/bin/env zsh

source ${HOME}/.aliases
set -e

mkdir -p ${HOME}/build
cd ${HOME}/build

wget http://luajit.org/download/LuaJIT-2.1.0-beta1.tar.gz
tar zxf LuaJIT-2.1.0-beta1.tar.gz
cd LuaJIT-2.1.0-beta1

make PREFIX=$HOME/.local/usr -j
make install PREFIX=$HOME/.local/usr

ln -sf luajit-2.1.0-beta1 /home/splinter/.local/usr/bin/luajit

cd ../..
rm ${HOME}/build -rf
