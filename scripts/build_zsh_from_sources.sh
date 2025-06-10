PREFIX=${HOME}/.local.ubuntu

# https://gist.github.com/nicoulaj/715855/7fa178a4fa954f9a8a0201ee8e7dfa5611812bb0
#
# git clone git://zsh.git.sf.net/gitroot/zsh/zsh
# 
# cd zsh
# 
# # Some packages may be missing
# sudo apt-get install -y git-core gcc make autoconf yodl libncursesw5-dev texinfo

./Util/preconfig

# Options from Ubuntu Zsh package rules file (http://launchpad.net/ubuntu/+source/zsh)
./configure --prefix=$PREFIX \
            --mandir=$PREFIX/share/man \
            --bindir=$PREFIX/bin \
            --infodir=$PREFIX/share/info \
            --enable-maildir-support \
            --enable-max-jobtable-size=256 \
            --enable-function-subdirs \
            --enable-site-fndir=$PREFIX/share/zsh/site-functions \
            --enable-fndir=$PREFIX/share/zsh/functions \
            --with-tcsetpgrp \
            --with-term-lib="ncursesw" \
            --enable-cap \
            --enable-pcre \
            --enable-readnullcmd=pager \
            --enable-custom-patchlevel=Debian \
            LDFLAGS="-Wl,--as-needed -g"

make

make check

make install
