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
    git cmake python-dev
    """


class VimInstaller(Installer):
    def install(self):
        os.symlink(os.path.join(PWD, "all", "vimrc"), os.path.join(HOME, ".vimrc"))
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




def main():
    VimInstaller().install()


if __name__ == '__main__':
    main()
