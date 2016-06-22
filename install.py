#!/usr/bin/env python3
# encoding: utf-8

import os
import sys
import argparse
import subprocess as sb
from contextlib import contextmanager

ISLINUX = (sys.platform != 'darwin')

PWD = os.path.abspath(os.path.dirname(__file__))
HOME = os.path.expanduser("~")
LOCAL_BIN = os.path.join(HOME, ".local", "bin")
HOMEBREW_HOME = os.path.join(HOME, ".brew") if ISLINUX else os.path.join("usr", "local")
os.makedirs(LOCAL_BIN, exist_ok=True)

INSTALLERS = {}


@contextmanager
def PathGuard(path):
    prev = os.getcwd()
    os.chdir(path)
    yield
    os.chdir(prev)


def get_free_name(path):
    index = 0
    while True:
        freepath = path + ".{}".format(index)
        if not os.path.exists(freepath):
            return freepath
        index += 1


def symlink(source, destination):
    if os.path.lexists(destination):
        if os.path.islink(destination) and not os.path.exists(destination):  # broken symbolic link
            os.remove(destination)
        elif os.path.realpath(source) == os.path.realpath(destination):  # same link
            return
        else:
            olddestination = get_free_name(destination + ".old")
            print("Warning: {} path already exists, move it to {}".format(destination, olddestination))
            os.rename(destination, olddestination)
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


class GitConfigInstaller(Installer):
    name = 'git'
    gitconfig = os.path.join(HOME, ".gitconfig")
    gitignore = os.path.join(HOME, ".gitignore")

    @classmethod
    def install(cls):
        symlink(os.path.join(PWD, "all", "git", "gitconfig"), cls.gitconfig)
        symlink(os.path.join(PWD, "all", "git", "gitignore"), cls.gitignore)


class OhMyZshInstaller(Installer):
    name = 'zsh'
    bashrc = os.path.join(HOME, ".bashrc")
    zshrc = os.path.join(HOME, ".zshrc")
    bashline = '[ -z "$PS1" ] && return\n\nexec zsh'
    themes = os.path.join(HOME, ".oh-my-zsh", "custom", "themes")
    mytheme = os.path.join(themes, "mytheme.zsh-theme")

    @classmethod
    def install(cls):
        if os.path.exists(cls.bashrc) and open(cls.bashrc).read().strip() != cls.bashline:
            os.rename(cls.bashrc, get_free_name(cls.bashrc + ".old"))
            with open(cls.bashrc, 'w') as bashrc:
                bashrc.write(cls.bashline)
        symlink(os.path.join(PWD, "all", "zsh", "zshrc"), cls.zshrc)

        os.makedirs(cls.themes, exist_ok=True)
        symlink(os.path.join(PWD, "all", "zsh", "mytheme.zsh-theme"), cls.mytheme)


class VimInstaller(Installer):
    name = 'vim'
    vimrc = os.path.join(HOME, ".vimrc")
    llvmpath = os.path.join(HOMEBREW_HOME, "Cellar", "llvm38", "3.8.0")

    @classmethod
    def install(cls):
        symlink(os.path.join(PWD, "all", "vim", "vimrc"), cls.vimrc)
        sb.call(["vim", "-e", "+PluginInstall", "+qall"])
        os.makedirs(os.path.join(HOME, ".vim", "undo"), exist_ok=True)
        os.makedirs(os.path.join(HOME, ".vim", "swap"), exist_ok=True)
        with PathGuard(os.path.join(HOME, ".vim", "bundle", "YouCompleteMe")):
            sb.call(["git", "submodule", "update", "--init", "--recursive"])

            prefix = sb.check_output(['python-config', '--prefix']).strip().decode('utf8')
            py2library = os.path.join(prefix, 'lib', 'libpython2.7' + '.so' if ISLINUX else '.dylib')
            py2include = os.path.join(prefix, 'include', 'python2.7')
            custom_env = os.environ.copy()
            custom_env['EXTRA_CMAKE_ARGS'] = \
                '-DPYTHON_LIBRARY={} -DPYTHON_INCLUDE_DIR={}'.format(py2library, py2include)
            sb.call(["./install.py", "--clang-completer", "--system-libclang"], env=custom_env)

        with PathGuard(os.path.join(HOME, ".vim", "bundle", "color_coded")):
            sb.call(["mkdir", "-p", "build"])
            with PathGuard("build"):
                sb.call(["cmake", "-DCUSTOM_CLANG=1", "-DLLVM_ROOT_PATH={}".format(cls.llvmpath), ".."])
                sb.call(["make", "-j"])
                sb.call(["make", "install"])
                sb.call(["make", "clean"])
        open(os.path.join(HOME, ".color_coded"), 'w').write('-fcolor-diagnostics')


class TmuxInstaller(Installer):
    name = 'tmux'
    tmuxconf = os.path.join(HOME, ".tmux.conf")

    @classmethod
    def install(cls):
        symlink(os.path.join(PWD, "all", "tmux", "tmux.conf"), cls.tmuxconf)
        symlink(
            os.path.join(PWD, "all", "tmux", "tmux-vim-select-pane"),
            os.path.join(LOCAL_BIN, "tmux-vim-select-pane")
        )


class SSHInstaller(Installer):
    name = "ssh"

    @staticmethod
    def install():
        if ISLINUX:
            for filename in ['pbcopy', 'pbpaste', 'pbopen']:
                symlink(
                    os.path.join(PWD, "all", "ssh", filename + "-remote"),
                    os.path.join(LOCAL_BIN, filename)
                )
        else:
            symlink(os.path.join(PWD, "all", "ssh", "pbopen-local"), os.path.join(LOCAL_BIN, "pbopen"))

        symlink(os.path.join(PWD, "all", "ssh", "notebook.sh"), os.path.join(LOCAL_BIN, "notebook"))
        symlink(os.path.join(PWD, "all", "ssh", "config"), os.path.join(HOME, ".ssh", "config"))
        os.chmod(os.path.join(HOME, ".ssh", "config"), 0o644)


class ConfigsInstall(Installer):
    name = 'configs'

    @staticmethod
    def install():
        OhMyZshInstaller.install()
        SSHInstaller.install()
        GitConfigInstaller.install()
        TmuxInstaller.install()
        VimInstaller.install()


def parse_args():
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
    args = parse_args()
    action = {
        'install': install,
        'remove': remove,
        'list': show
    }
    action[args.action](args)


if __name__ == '__main__':
    main()
