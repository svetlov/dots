#!/usr/bin/env python
# encoding: utf-8

import os
import argparse
import subprocess as sb
from contextlib import contextmanager


PWD = os.getcwd()
HOME = os.path.expanduser("~")

@contextmanager
def PathGuard(path):
    prev = os.getcwd()
    os.chdir(path)
    yield
    os.chdir(prev)


class Installer(object):
    def install(self):
        pass

    def unistall(self):
        pass


class DebianInstaller(Installer):
    """
    git cmake python-dev gcc g++ zsh
    """


class OhMyZSHInstaller(Installer):
    def install(self):
        with open(os.path.join(HOME, ".bashrc"), 'w') as bashrc:
            bashrc.write('[ -z "$PS1" ] && return\n\nexec zsh')
        sb.call([
            "git", "clone",
            "git://github.com/robbyrussell/oh-my-zsh.git",
            os.path.join(HOME, ".oh-my-zsh")
        ])
        os.symlink(
            os.path.join(PWD, "all", "zsh", "zshrc"),
            os.path.join(HOME, ".zshrc")
        )
        themes = os.path.join(HOME, ".oh-my-zsh", "custom", "themes")
        os.mkdir(themes)
        os.symlink(
            os.path.join(PWD, "all", "zsh", "mytheme.zsh-theme"),
            os.path.join(themes, "mytheme.zsh-theme")
        )



class VimInstaller(Installer):
    def install(self):
        os.symlink(
            os.path.join(PWD, "all", "vim", "vimrc"),
            os.path.join(HOME, ".vimrc")
        )
        sb.call([
            "git", "clone",
            "https://github.com/VundleVim/Vundle.vim.git",
            os.path.join(HOME, ".vim/bundle/Vundle.vim")
        ])
        sb.call(["vim", "-e", "+PluginInstall", "+qall"])
        os.mkdir(os.path.join(HOME, ".vim", "undo"))
        os.mkdir(os.path.join(HOME, ".vim", "swap"))
        with PathGuard(os.path.join(HOME, ".vim", "bundle", "YouCompleteMe")):
            sb.call(["git", "submodule", "update", "--init", "--recursive"])
            sb.call(["./install.sh", "--clang-completer"])
        sb.call(["zsh"])

def main():
    # VimInstaller().install()
    OhMyZSHInstaller().install()


if __name__ == '__main__':
    main()
