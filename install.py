#!/usr/bin/env python3
# encoding: utf-8

import os
import argparse
import subprocess as sb
from contextlib import contextmanager


PWD = os.path.abspath(__file__.rsplit(os.path.sep)[0])
HOME = os.path.expanduser("~")
INSTALLERS = {}


@contextmanager
def PathGuard(path):
    prev = os.getcwd()
    os.chdir(path)
    yield
    os.chdir(prev)

def forceRemove(filename):
    if os.path.exists(filename):
        os.remove(filename)

def symlink(source, destination, force=True):
    if force:
        forceRemove(destination)
    os.symlink(source, destination)


class RegisterInstallerMetaclass(type):
    def __init__(cls, name, bases, dct):
        super(RegisterInstallerMetaclass, cls).__init__(name, bases, dct)
        if cls.name is not None:
            INSTALLERS[cls.name] = cls


class Installer(object, metaclass=RegisterInstallerMetaclass):
    name = None
    description = None

    @staticmethod
    def install():
        raise NotImplementedError

    @staticmethod
    def uninstall():
        raise NotImplementedError


class DebianInstaller(Installer):
    """
    git cmake python-dev python python3 gcc g++ zsh virtualenvwrapper
    python-pip python3-pip
    exuberant-ctags  " for vim tagbar
    """
    name = 'debian'


class LibraryInstaller(Installer):
    name = 'libs'

    @staticmethod
    def install():
        with PathGuard(os.path.join(PWD, 'all', 'libs')):
            sb.call(['./install-cmake.sh'])
            sb.call(['./install-tinfo.sh'])
            sb.call(['./install-ncurses.sh'])
            sb.call(['./install-readline.sh'])
            sb.call(['./install-libevent.sh'])
            sb.call(['./install-lua.sh'])
            sb.call(['./install-luajit.sh'])
            sb.call(['./install-clang.sh'])


class GitConfigInstaller(Installer):
    name = 'git'

    @staticmethod
    def install():
        symlink(
            os.path.join(PWD, "all", "git", "gitconfig"),
            os.path.join(HOME, ".gitconfig")
        )


class OhMyZSHInstaller(Installer):
    name = 'zsh'

    @staticmethod
    def install():
        with open(os.path.join(HOME, ".bashrc"), 'w') as bashrc:
            bashrc.write('[ -z "$PS1" ] && return\n\nexec zsh')
        sb.call([
            "git", "clone",
            "git://github.com/robbyrussell/oh-my-zsh.git",
            os.path.join(HOME, ".oh-my-zsh")
        ])
        symlink(
            os.path.join(PWD, "all", "zsh", "zshrc"),
            os.path.join(HOME, ".zshrc")
        )
        themes = os.path.join(HOME, ".oh-my-zsh", "custom", "themes")
        os.makedirs(themes, exist_ok=True)
        symlink(
            os.path.join(PWD, "all", "zsh", "mytheme.zsh-theme"),
            os.path.join(themes, "mytheme.zsh-theme")
        )


class VimInstaller(Installer):
    name = 'vim'

    @staticmethod
    def install():
        # with PathGuard(os.path.join(PWD, 'all', 'vim')):
        #     sb.call('./install-vim.sh')
        # symlink(
        #     os.path.join(PWD, "all", "vim", "vimrc"),
        #     os.path.join(HOME, ".vimrc")
        # )
        # sb.call(["vim", "-e", "+PluginInstall", "+qall"])
        # os.makedirs(os.path.join(HOME, ".vim", "undo"), exist_ok=True)
        # os.makedirs(os.path.join(HOME, ".vim", "swap"), exist_ok=True)
        # with PathGuard(os.path.join(HOME, ".vim", "bundle", "YouCompleteMe")):
        #     sb.call(["git", "submodule", "update", "--init", "--recursive"])
        #     sb.call(["./install.py", "--clang-completer"])

        with PathGuard(os.path.join(HOME, ".vim", "bundle", "color_coded")):
            sb.call(["mkdir", "build"])
            with PathGuard("build"):
                sb.call(["cmake", "-DCMAKE_PREFIX_PATH=~/.local/usr/", ".."])
                sb.call(["make"])
                sb.call(["make", "install"])
                sb.call(["make", "clean"])
                sb.call(["make", "clean_clang"])


class TmuxInstaller(Installer):
    name = 'tmux'

    @staticmethod
    def install():
        with PathGuard(os.path.join(PWD, "all", "tmux")):
            sb.call(["./install.sh"])
        symlink(
            os.path.join(PWD, "all", "tmux", "tmux.conf"),
            os.path.join(HOME, ".tmux.conf")
        )

        localBin = os.path.join(HOME, ".local", "usr", "bin")
        os.makedirs(localBin, exist_ok=True)
        for filename in ['pbcopy', 'pbpaste']:
            symlink(
                os.path.join(PWD, "all", "tmux", filename),
                os.path.join(localBin, filename)
            )


def parseArgs():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(help='actions', dest='action')
    install = subparsers.add_parser('install')
    remove = subparsers.add_parser('remove')
    show = subparsers.add_parser('list')

    for p in [install, remove]:
        p.add_argument(
            'names', type=str, metavar='package',
            nargs='+', choices=INSTALLERS.keys()
        )
    return parser.parse_args()


def install(args):
    for name in args.names:
        INSTALLERS[name].install()


def remove(args):
    for name in args.names:
        INSTALLERS[name].uninstall()


def show(args):
    for name, installer in INSTALLERS.items():
        print("\t{}\t{}".format(name, installer.description))


def main():
    args = parseArgs()
    action = {
        'install': install,
        'remove': remove,
        'list': show
    }
    action[args.action](args)


if __name__ == '__main__':
    main()
