#!/usr/bin/env zsh

mkdir -p ${HOME}/build
cd ${HOME}/build

source ${HOME}/.aliases

git clone https://github.com/vim/vim.git
cd vim
cd src

./configure --prefix=$HOME/.local \
            --with-features=huge \
            --enable-largefile \
            --disable-netbeans \
            --enable-pythoninterp \
            --with-python-config-dir=/usr/lib/python2.7/config \
            --enable-luainterp \
            --with-lua-prefix=$HOME/.local/usr \
            --enable-fail-if-missing \
            --enable-cscope

make -j install

cd ../..
rm -rf ${HOME}/build
