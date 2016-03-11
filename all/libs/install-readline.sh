#!/usr/bin/env zsh

source ${HOME}/.aliases
set -e

mkdir -p ${HOME}/build
cd ${HOME}/build

readlineurl=http://git.savannah.gnu.org/cgit/readline.git/snapshot/readline-master.tar.gz

curl -o readline.tar.gz $readlineurl
tar -xzf readline.tar.gz
cd readline-master
./configure CFLAS='-fPIC' --prefix=$HOME/.local/usr --with-curses
make SHLIB_LIBS='-lncurses -ltinfo' CFLAGS='-fPIC' -j all
make install

cd ../..
rm ${HOME}/build -rf
