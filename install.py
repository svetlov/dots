#!/usr/bin/env python3
# encoding: utf-8

import os
import sys
import argparse
import subprocess as sb
import contextlib

ISLINUX = sys.platform.startswith("linux")
ISWSL = ISLINUX and (
    "WSL_DISTRO_NAME" in os.environ
    or "microsoft" in os.uname().release.lower()
)

PWD = os.path.abspath(os.path.dirname(__file__))
HOME = os.path.expanduser("~")
LOCAL = os.path.join(HOME, ".local")
LOCAL_BIN = os.path.join(LOCAL, "bin")

os.makedirs(LOCAL, exist_ok=True)
os.makedirs(LOCAL_BIN, exist_ok=True)

INSTALLERS = {}


@contextlib.contextmanager
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
    if not os.path.exists(source):
        print("Warning: source path does not exist, skipping: {}".format(source))
        return
    if os.path.lexists(destination):
        if os.path.islink(destination) and not os.path.exists(
            destination
        ):  # broken symbolic link
            os.remove(destination)
        elif os.path.realpath(source) == os.path.realpath(destination):  # same link
            return
        else:
            olddestination = get_free_name(destination + ".old")
            print(
                "Warning: {} path already exists, move it to {}".format(
                    destination, olddestination
                )
            )
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
    name = "git"
    gitconfig = os.path.join(HOME, ".gitconfig")
    gitignore = os.path.join(HOME, ".gitignore")

    @classmethod
    def install(cls):
        symlink(os.path.join(PWD, "all", "git", "gitconfig"), cls.gitconfig)
        symlink(os.path.join(PWD, "all", "git", "gitignore"), cls.gitignore)


class OhMyZshInstaller(Installer):
    name = "zsh"

    src_bashrc = os.path.join(PWD, "all", "zsh", "bashrc")
    dst_bashrc = os.path.join(HOME, ".bashrc")

    src_bash_profile = os.path.join(PWD, "all", "zsh", "bash_profile")
    dst_bash_profile = os.path.join(HOME, ".bash_profile")

    src_zprofile = os.path.join(PWD, "all", "zsh", "zprofile")
    dst_zprofile = os.path.join(HOME, ".zprofile")

    src_zshrc = os.path.join(PWD, "all", "zsh", "zshrc")
    dst_zshrc = os.path.join(HOME, ".zshrc")

    themes = os.path.join(HOME, ".oh-my-zsh", "custom", "themes")
    mytheme = os.path.join(themes, "mytheme.zsh-theme")

    @classmethod
    def install(cls):
        symlink(cls.src_bashrc, cls.dst_bashrc)
        symlink(cls.src_bash_profile, cls.dst_bash_profile)
        symlink(cls.src_zshrc, cls.dst_zshrc)
        symlink(cls.src_zprofile, cls.dst_zprofile)

        os.makedirs(cls.themes, exist_ok=True)
        symlink(os.path.join(PWD, "all", "zsh", "mytheme.zsh-theme"), cls.mytheme)

        # Install NPM configuration
        symlink(
            os.path.join(PWD, "all", "zsh", "npmrc"),
            os.path.join(HOME, ".npmrc")
        )


class NVimInstaller(Installer):
    name = "nvim"

    @classmethod
    def install(cls):
        os.makedirs(os.path.join(HOME, ".config", "nvim"), exist_ok=True)
        os.makedirs(
            os.path.join(HOME, ".config", "nvim", "lua", "plugins"), exist_ok=True
        )
        os.makedirs(os.path.join(HOME, ".config", "nvim", "syntax"), exist_ok=True)
        os.makedirs(os.path.join(HOME, ".config", "nvim", "undo"), exist_ok=True)
        os.makedirs(os.path.join(HOME, ".config", "nvim", "swap"), exist_ok=True)

        symlink(
            os.path.join(PWD, "all", "vim", "init.lua"),
            os.path.join(HOME, ".config", "nvim", "init.lua"),
        )
        symlink(
            os.path.join(PWD, "all", "vim", "core.lua"),
            os.path.join(HOME, ".config", "nvim", "lua", "plugins", "core.lua"),
        )

        if ISWSL:
            symlink(
                os.path.join(PWD, "all", "vim", "wslcopy.sh"),
                os.path.join(LOCAL_BIN, "wslcopy.sh"),
            )


class TmuxInstaller(Installer):
    name = "tmux"
    tmuxconf = os.path.join(HOME, ".tmux.conf")

    @classmethod
    def install(cls):
        os.makedirs(os.path.join(HOME, ".tmux"), exist_ok=True)
        symlink(os.path.join(PWD, "all", "tmux", "tmux.conf"), cls.tmuxconf)
        symlink(
            os.path.join(PWD, "all", "tmux", "tmux-vim-select-pane"),
            os.path.join(LOCAL_BIN, "tmux-vim-select-pane"),
        )
        symlink(
            os.path.join(PWD, "all", "tmux", "plugins"),
            os.path.join(HOME, ".tmux", "plugins"),
        )


class VSCodeInstaller(Installer):
    name = "vscode"
    VSCODE_SETTINGS_DIR = os.path.join(
        HOME, "Library", "Application Support", "Code", "User"
    )

    @classmethod
    def install(cls):
        os.makedirs(cls.VSCODE_SETTINGS_DIR, exist_ok=True)
        for config in ("settings.json", "keybindings.json"):
            symlink(
                os.path.join(PWD, "all", "vscode", config),
                os.path.join(cls.VSCODE_SETTINGS_DIR, config),
            )


class KarabinerInstaller(Installer):
    name = "karabiner"
    KARABINER_DIR = os.path.join(HOME, ".config", "karabiner")

    @classmethod
    def install(cls):
        if ISLINUX:
            return
        os.makedirs(cls.KARABINER_DIR, exist_ok=True)
        symlink(
            os.path.join(PWD, "all", "karabiner", "karabiner.json"),
            os.path.join(cls.KARABINER_DIR, "karabiner.json"),
        )


class CodeAgentsInstaller(Installer):
    name = "code-agents"
    CODEX_DIR = os.path.join(HOME, ".codex")
    CLAUDE_DIR = os.path.join(HOME, ".claude")
    DIPPY_DIR = os.path.join(HOME, ".dippy")
    WORKMUX_DIR = os.path.join(HOME, ".config", "workmux")

    @classmethod
    def install(cls):
        os.makedirs(cls.CODEX_DIR, exist_ok=True)
        os.makedirs(cls.CLAUDE_DIR, exist_ok=True)
        os.makedirs(cls.DIPPY_DIR, exist_ok=True)
        os.makedirs(cls.WORKMUX_DIR, exist_ok=True)

        symlink(
            os.path.join(PWD, "all", "code-agents", "codex.toml"),
            os.path.join(cls.CODEX_DIR, "config.toml"),
        )
        symlink(
            os.path.join(PWD, "all", "code-agents", "prompts"),
            os.path.join(cls.CODEX_DIR, "prompts"),
        )
        symlink(
            os.path.join(PWD, "all", "code-agents", "prompts"),
            os.path.join(cls.CLAUDE_DIR, "commands"),
        )
        symlink(
            os.path.join(PWD, "all", "code-agents", "CLAUDE.md"),
            os.path.join(cls.CLAUDE_DIR, "CLAUDE.md"),
        )
        # Same shared conventions file consumed by Codex as AGENTS.md
        # (https://developers.openai.com/codex/guides/agents-md).
        symlink(
            os.path.join(PWD, "all", "code-agents", "CLAUDE.md"),
            os.path.join(cls.CODEX_DIR, "AGENTS.md"),
        )
        symlink(
            os.path.join(PWD, "all", "code-agents", "claude-settings.json"),
            os.path.join(cls.CLAUDE_DIR, "settings.json"),
        )
        symlink(
            os.path.join(PWD, "all", "code-agents", "hooks"),
            os.path.join(cls.CLAUDE_DIR, "hooks"),
        )
        # Fable research/architect agent definitions (launched as background
        # agents: `claude --bg --agent ir-researcher "<topic>"`)
        symlink(
            os.path.join(PWD, "all", "code-agents", "agents"),
            os.path.join(cls.CLAUDE_DIR, "agents"),
        )

        # Dippy (Claude Code bash safety hook) config
        symlink(
            os.path.join(PWD, "all", "code-agents", "dippy-config"),
            os.path.join(cls.DIPPY_DIR, "config"),
        )

        # Install paper summarization scripts (entire directory)
        paper_sum_src = os.path.join(PWD, "all", "code-agents", "paper-summarization")
        paper_sum_dst = os.path.join(cls.CODEX_DIR, "paper-summarization")
        symlink(paper_sum_src, paper_sum_dst)

        # Install Ubuntu dependencies reference
        ubuntu_deps = os.path.join(PWD, "all", "code-agents", "ubuntu-deps.json")
        symlink(ubuntu_deps, os.path.join(cls.CODEX_DIR, "ubuntu-deps.json"))

        # Workmux global config
        symlink(
            os.path.join(PWD, "all", "code-agents", "workmux.yaml"),
            os.path.join(cls.WORKMUX_DIR, "config.yaml"),
        )


class SSHInstaller(Installer):
    name = "ssh"

    @staticmethod
    def install():
        os.makedirs(os.path.join(HOME, ".ssh"), exist_ok=True)
        if ISLINUX:
            symlink(
                os.path.join(PWD, "all", "ssh", "pbcopy-remote.sh"),
                os.path.join(LOCAL_BIN, "pbcopy"),
            )
            symlink(
                os.path.join(PWD, "all", "ssh", "pbpaste-remote.sh"),
                os.path.join(LOCAL_BIN, "pbpaste"),
            )
            symlink(
                os.path.join(PWD, "all", "ssh", "pbopen.sh"),
                os.path.join(LOCAL_BIN, "pbopen"),
            )
        else:
            launch_agents_path = os.path.join(HOME, "Library", "LaunchAgents")
            os.makedirs(launch_agents_path, exist_ok=True)

            pbcopy_agent = os.path.join(launch_agents_path, "pbcopy.plist")
            sb.call(["launchctl", "unload", pbcopy_agent])
            symlink(os.path.join(PWD, "all", "ssh", "pbcopy.plist"), pbcopy_agent)
            sb.check_call(["launchctl", "load", pbcopy_agent])

            pbpaste_agent = os.path.join(launch_agents_path, "pbpaste.plist")
            sb.call(["launchctl", "unload", pbpaste_agent])
            symlink(os.path.join(PWD, "all", "ssh", "pbpaste.plist"), pbpaste_agent)
            sb.check_call(["launchctl", "load", pbpaste_agent])

            pbopen_agent = os.path.join(launch_agents_path, "pbopen.plist")
            sb.call(["launchctl", "unload", pbopen_agent])
            symlink(os.path.join(PWD, "all", "ssh", "pbopen.plist"), pbopen_agent)
            sb.check_call(["launchctl", "load", pbopen_agent])

            notebook_agent = os.path.join(launch_agents_path, "notebook.plist")
            sb.call(["launchctl", "unload", notebook_agent])
            symlink(os.path.join(PWD, "all", "ssh", "notebook.plist"), notebook_agent)
            sb.check_call(["launchctl", "load", notebook_agent])

        symlink(
            os.path.join(PWD, "all", "ssh", "notebook.sh"),
            os.path.join(LOCAL_BIN, "notebook"),
        )
        symlink(
            os.path.join(PWD, "all", "ssh", "config"),
            os.path.join(HOME, ".ssh", "config"),
        )
        os.chmod(os.path.join(HOME, ".ssh", "config"), 0o644)


class MercurialInstaller(Installer):
    name = "hg"

    @staticmethod
    def install():
        symlink(os.path.join(PWD, "all", "hgrc"), os.path.join(HOME, ".hgrc"))


class ConfigsInstall(Installer):
    name = "configs"

    @staticmethod
    def install():
        OhMyZshInstaller.install()
        SSHInstaller.install()
        GitConfigInstaller.install()
        MercurialInstaller.install()
        TmuxInstaller.install()
        VSCodeInstaller.install()
        NVimInstaller.install()
        CodeAgentsInstaller.install()


def parse_args():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(help="actions", dest="action")
    install = subparsers.add_parser("install")
    remove = subparsers.add_parser("remove")
    show = subparsers.add_parser("list")

    for p in [install, remove]:
        p.add_argument(
            "names", type=str, metavar="package", nargs="+", choices=INSTALLERS.keys()
        )
    args = parser.parse_args()
    if args.action is None:
        parser.print_help()
        sys.exit(2)
    return args


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
    action = {"install": install, "remove": remove, "list": show}
    action[args.action](args)


if __name__ == "__main__":
    main()
