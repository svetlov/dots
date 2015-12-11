#!/bin/sh

mkdir ${HOME}/build
cd ${HOME}/build

curl -R -O http://www.lua.org/ftp/lua-5.3.2.tar.gz
tar zxf lua-5.3.2.tar.gz

cd lua-5.3.2
make -C src clean all SYSCFLAGS="-DLUA_USE_LINUX -fPIC" SYSLIBS="-Wl,-E -ldl -lreadline -lncurses"

make install INSTALL_TOP=$HOME/.local/usr

cd ../..

rm ${HOME}/build -r
