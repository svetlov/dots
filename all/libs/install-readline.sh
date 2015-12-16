#!/bin/sh

set -e

mkdir ${HOME}/build
cd ${HOME}/build

readlineurl=http://git.savannah.gnu.org/cgit/readline.git/snapshot/readline-master.tar.gz

wget $readlineurl -O readline.tar.gz
tar xvzf readline.tar.gz
cd readline-master
./configure CFLAS='-fPIC' --prefix=$HOME/.local/usr --with-curses
make SHLIB_LIBS='-lncurses -ltinfo' CFLAGS='-fPIC' -j shared static
make install

cd ../..
# rm ${HOME}/build -r
