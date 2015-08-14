#!/bin/bash

# Script for installing tmux on systems where you don't have root access.
# tmux will be installed in $HOME/local/bin.
# It's assumed that wget and a C/C++ compiler are installed.

# exit on error
set -e

TMUX_VERSION=1.9

# create our directories
mkdir -p $HOME/tmux_tmp
cd $HOME/tmux_tmp

# download source files for tmux, libevent, and ncurses
wget -O tmux-${TMUX_VERSION}.tar.gz http://sourceforge.net/projects/tmux/files/tmux/tmux-${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz/download
wget https://github.com/downloads/libevent/libevent/libevent-2.0.19-stable.tar.gz
wget ftp://ftp.gnu.org/gnu/ncurses/ncurses-5.9.tar.gz

# extract files, configure, and compile

############
# libevent #
############
tar xvzf libevent-2.0.19-stable.tar.gz
cd libevent-2.0.19-stable
./configure --prefix=$HOME/.local/usr --disable-shared
make
make install
cd ..

############
# ncurses  #
############
tar xvzf ncurses-5.9.tar.gz
cd ncurses-5.9
./configure --prefix=$HOME/.local/usr/
make
make install
cd ..

############
# tmux     #
############
tar xvzf tmux-${TMUX_VERSION}.tar.gz
cd tmux-${TMUX_VERSION}
./configure CFLAGS="-I$HOME/.local/usr/include -I$HOME/.local/usr/include/ncurses" LDFLAGS="-L$HOME/.local/usr/lib -L$HOME/.local/usr/include/ncurses -L$HOME/.local/usr/include"
CPPFLAGS="-I$HOME/.local/usr/include -I$HOME/.local/usr/include/ncurses" LDFLAGS="-static -L$HOME/.local/usr/include -L$HOME/.local/usr/include/ncurses -L$HOME/.local/usr/lib" make
cp tmux $HOME/.local/usr/bin
cd ..

# cleanup
rm -rf $HOME/tmux_tmp

echo "$HOME/.local/usr/bin/tmux is now available. You can optionally add $HOME/.local/usr/bin to your PATH."
