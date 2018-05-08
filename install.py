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
LOCAL = os.path.join(HOME, ".local")
LOCAL_BIN = os.path.join(LOCAL, "bin")

os.makedirs(LOCAL, exist_ok=True)
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

    src_bashrc = os.path.join(PWD, 'all', 'zsh', 'bashrc')
    dst_bashrc = os.path.join(HOME, ".bashrc")

    src_zshrc = os.path.join(PWD, 'all', 'zsh', 'zshrc')
    dst_zshrc = os.path.join(HOME, ".zshrc")

    themes = os.path.join(HOME, ".oh-my-zsh", "custom", "themes")
    mytheme = os.path.join(themes, "mytheme.zsh-theme")

    @classmethod
    def install(cls):
        symlink(cls.src_bashrc, cls.dst_bashrc)
        symlink(cls.src_zshrc, cls.dst_zshrc)

        os.makedirs(cls.themes, exist_ok=True)
        symlink(os.path.join(PWD, "all", "zsh", "mytheme.zsh-theme"), cls.mytheme)


class VimInstaller(Installer):
    name = 'vim'
    vimrc = os.path.join(HOME, ".vimrc")

    @classmethod
    def install(cls):
        symlink(os.path.join(PWD, "all", "vim", "vimrc"), cls.vimrc)
        sb.call(["vim", "-e", "+PluginInstall", "+qall"])

        os.makedirs(os.path.join(HOME, ".vim", "syntax"), exist_ok=True)
        os.makedirs(os.path.join(HOME, ".vim", "undo"), exist_ok=True)
        os.makedirs(os.path.join(HOME, ".vim", "swap"), exist_ok=True)

        symlink(
            os.path.join(PWD, "all", "vim", "danet-config.vim"),
            os.path.join(HOME, ".vim", "syntax", "danet-config.vim")
        )

        env = os.environ.copy()
        env["CC"] = os.environ["CLANG39_CC"]
        env["CXX"] = os.environ["CLANG39_CXX"]

        with PathGuard(os.path.join(HOME, ".vim", "bundle", "YouCompleteMe")):
            sb.call(["git", "submodule", "update", "--init", "--recursive"], env=env)
            sb.call(["./install.py", "--clang-completer"], env=env)

        with PathGuard(os.path.join(HOME, ".vim", "bundle", "color_coded")):
            sb.call(["mkdir", "-p", "build"])
            with PathGuard("build"):
                sb.call(["cmake", "-DCMAKE_PREFIX_PATH={}".format(LOCAL), ".."], env=env)
                sb.call(["make", "-j"], env=env)
                sb.call(["make", "install"], env=env)
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
            symlink(os.path.join(PWD, "all", "ssh","pbcopy-remote.sh"), os.path.join(LOCAL_BIN, "pbcopy"))
            symlink(os.path.join(PWD, "all", "ssh","pbpaste-remote.sh"), os.path.join(LOCAL_BIN, "pbpaste"))
            symlink(os.path.join(PWD, "all", "ssh","pbopen.sh"), os.path.join(LOCAL_BIN, "pbopen"))
        else:
            launch_agents_path = os.path.join(HOME, "Library", "LaunchAgents")

            pbcopy_agent = os.path.join(launch_agents_path, "pbcopy.plist")
            sb.call(['launchctl', 'unload', pbcopy_agent])
            symlink(os.path.join(PWD, "all", "ssh", "pbcopy.plist"), pbcopy_agent)
            sb.check_call(['launchctl', 'load', pbcopy_agent])

            pbpaste_agent = os.path.join(launch_agents_path, "pbpaste.plist")
            sb.call(['launchctl', 'unload', pbpaste_agent])
            symlink(os.path.join(PWD, "all", "ssh", "pbpaste.plist"), pbpaste_agent)
            sb.check_call(['launchctl', 'load', pbpaste_agent])

            pbopen_agent = os.path.join(launch_agents_path, "pbopen.plist")
            sb.call(['launchctl', 'unload', pbopen_agent])
            symlink(os.path.join(PWD, "all", "ssh", "pbopen.plist"), pbopen_agent)
            sb.check_call(['launchctl', 'load', pbopen_agent])

            notebook_agent = os.path.join(launch_agents_path, "notebook.plist")
            sb.call(['launchctl', 'unload', notebook_agent])
            symlink(os.path.join(PWD, "all", "ssh", "notebook.plist"), notebook_agent)
            sb.check_call(['launchctl', 'load', notebook_agent])

        symlink(os.path.join(PWD, "all", "ssh", "notebook.sh"), os.path.join(LOCAL_BIN, "notebook"))
        symlink(os.path.join(PWD, "all", "ssh", "config"), os.path.join(HOME, ".ssh", "config"))
        os.chmod(os.path.join(HOME, ".ssh", "config"), 0o644)


class MercurialInstaller(Installer):
    name = 'hg'

    @staticmethod
    def install():
        symlink(os.path.join(PWD, "all", "hgrc"), os.path.join(HOME, ".hgrc"))


class ConfigsInstall(Installer):
    name = 'configs'

    @staticmethod
    def install():
        OhMyZshInstaller.install()
        SSHInstaller.install()
        GitConfigInstaller.install()
        MercurialInstaller.install()
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
