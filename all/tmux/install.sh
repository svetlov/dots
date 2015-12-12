#!/bin/bash

# Script for installing tmux on systems where you don't have root access.
# tmux will be installed in $HOME/local/bin.
# It's assumed that wget and a C/C++ compiler are installed.

# exit on error
set -e

# create our directories
mkdir -p ${HOME}/build
cd ${HOME}/build

# download source files for tmux, libevent, and ncurses
wget -O tmux-1.9.tar.gz http://sourceforge.net/projects/tmux/files/tmux/tmux-1.9/tmux-1.9.tar.gz/download
tar xvzf tmux-1.9.tar.gz

cd tmux-1.9
./configure --prefix ${HOME}/.local/usr CFLAGS="-I${HOME}/.local/usr/include/ncurses"
CFLAGS="-I$HOME/.local/usr/include/ncurses:${CFLAGS}" make -j
make install
cd ../..

# cleanup
rm -rf ${HOME}/build
