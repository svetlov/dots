#!/bin/sh

mkdir -p ${HOME}/build
cd ${HOME}/build

wget https://ftp.gnu.org/gnu/gcc/gcc-4.9.3/gcc-4.9.3.tar.bz2
wget https://ftp.gnu.org/gnu/gcc/gcc-4.9.3/gcc-4.9.3.tar.bz2.sig
wget https://ftp.gnu.org/gnu/gnu-keyring.gpg

signature_invalid=`gpg --verify --no-default-keyring --keyring ./gnu-keyring.gpg gcc-4.9.3.tar.bz2.sig`
if [ $signature_invalid ]; then
    echo "Invalid signature";
    exit 1;
 fi

tar -xvjf gcc-4.9.3.tar.bz2
cd gcc-4.9.3

./contrib/download_prerequisites

cd ..
mkdir gcc-4.9.3-build
cd gcc-4.9.3-build

$PWD/../gcc-4.9.3/configure --prefix=${HOME}/.local/usr --libdir=${HOME}/.local/usr/lib/gcc/4.9 --enable-languages=c,c++ --program-suffix=-4.9 --disable-multilib --disable-bootstrap
make -j
make install

cd ${HOME}
rm ${HOME}/build -rf
