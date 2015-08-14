#!/usr/bin/env python3
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
    git cmake python-dev python python3 gcc g++ zsh virtualenvwrapper
    """


class GitConfigInstaller(Installer):
    def install(self):
        os.symlink(
            os.path.join(PWD, "all", "git", "gitconfig"),
            os.path.join(HOME, ".gitconfig")
        )


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


class TmuxInstaller(Installer):
    def install(self):
        with PathGuard(os.path.join(PWD, "all", "tmux")):
            sb.call(["./install.sh"])
        os.symlink(
            os.path.join(PWD, "all", "tmux", "tmux.conf"),
            os.path.join(HOME, ".tmux.conf")
        )

        localBin = os.path.join(HOME, ".local", "usr", "bin")
        os.makedirs(localBin, exist_ok=True)
        for filename in ['pbcopy', 'pbpaste']:
            os.symlink(
                os.path.join(PWD, "all", "tmux", filename),
                os.path.join(localBin, filename)
            )


def main():
    # VimInstaller().install()
    # OhMyZSHInstaller().install()
    # GitConfigInstaller().install()
    TmuxInstaller().install()


if __name__ == '__main__':
    main()
