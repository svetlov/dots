#!/usr/bin/env bash
set -euo pipefail

DOTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() {
    echo ""
    echo "==> $1"
    echo ""
}

ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    BREW_PREFIX=/opt/homebrew
else
    BREW_PREFIX=/usr/local
fi

# Prepend the paths of things we install so later steps can find them in the
# same shell. A fresh non-login bash has none of these on PATH, which broke
# every `command -v` check before we got around to symlinking .zprofile/.zshrc.
export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

# Step 1: Xcode Command Line Tools (git, compilers, headers)
ensure_xcode_clt() {
    if xcode-select -p >/dev/null 2>&1; then
        info "Xcode Command Line Tools already installed"
        return
    fi
    info "Installing Xcode Command Line Tools — accept the GUI prompt to proceed"
    xcode-select --install || true
    until xcode-select -p >/dev/null 2>&1; do
        sleep 5
    done
}

# Step 2: Homebrew
install_homebrew() {
    # File-based check so we don't try to re-install just because PATH is bare
    if [ -x "$BREW_PREFIX/bin/brew" ]; then
        info "Homebrew already installed"
    else
        info "Installing Homebrew"
        NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    eval "$("$BREW_PREFIX/bin/brew" shellenv)"
}

# Step 3: Brew packages (base + dynamic from ubuntu-deps.json mapped to brew names)
install_brew_packages() {
    info "Installing brew packages"

    local base_packages=(
        zsh tmux git wget keychain
        cmake gettext
        ripgrep fd
        python imagemagick luarocks
        jq
    )

    # ubuntu-deps.json → brew equivalents
    # poppler-utils (pdftotext) → poppler
    # pciutils (lspci)          → skipped (N/A on macOS)
    # trash-cli                 → trash-cli
    local extra_packages=(poppler trash-cli)

    brew install "${base_packages[@]}" "${extra_packages[@]}"
}

# Step 4: Neovim (brew handles version pinning)
install_neovim() {
    if command -v nvim >/dev/null 2>&1; then
        info "Neovim already installed ($(nvim --version | head -1))"
    else
        info "Installing Neovim"
        brew install neovim
    fi
}

# Step 5: nvm + Node.js (curl installer, same as Linux for $HOME/.nvm parity)
install_nvm_node() {
    if [ -d "$HOME/.nvm" ]; then
        info "nvm already installed, skipping"
    else
        info "Installing nvm"
        PROFILE=/dev/null bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash'
    fi

    export NVM_DIR="$HOME/.nvm"

    # Disable strict mode for the nvm block: nvm.sh's auto-`use` internally
    # does `set -e; return 11` when .npmrc has a conflicting `prefix=`
    # (intentional, see [[npm-prefix-local]]). That kills our script even with
    # `|| true` guards. Restore strict mode at the end of the block.
    set +eu
    # shellcheck disable=SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

    # Manually surface the latest installed Node version on PATH; nvm.sh would
    # normally do this via auto-`use`, but it bailed before getting there.
    if [ -d "$NVM_DIR/versions/node" ]; then
        node_ver=$(ls -1 "$NVM_DIR/versions/node" 2>/dev/null | sort -V | tail -1)
        if [ -n "$node_ver" ] && [ -x "$NVM_DIR/versions/node/$node_ver/bin/node" ]; then
            export PATH="$NVM_DIR/versions/node/$node_ver/bin:$PATH"
        fi
    fi

    if command -v node >/dev/null 2>&1; then
        info "Node.js already installed ($(node --version)), skipping"
    else
        info "Installing Node.js LTS via nvm"
        nvm install --lts
    fi
    set -eu
}

# Step 6: Symlink npmrc before any global npm install reads it
symlink_npmrc() {
    info "Symlinking npmrc"
    ln -sf "$DOTS_DIR/all/zsh/npmrc" "$HOME/.npmrc"
}

# Step 7: AI CLI tools
install_ai_tools() {
    info "Installing AI CLI tools"

    # Check both PATH and the npm-prefix bindir (.npmrc points global bins
    # at ~/.local/bin, which may not yet be on PATH within this script)
    if command -v claude >/dev/null 2>&1 || [ -e "$HOME/.local/bin/claude" ]; then
        echo "claude-code already installed, skipping"
    else
        npm install -g @anthropic-ai/claude-code
    fi

    if command -v codex >/dev/null 2>&1 || [ -e "$HOME/.local/bin/codex" ]; then
        echo "codex already installed, skipping"
    else
        npm install -g @openai/codex
    fi

    local dippy_dir="$HOME/.local/share/dippy"
    if [[ -d "$dippy_dir" ]]; then
        echo "dippy already installed, updating"
        git -C "$dippy_dir" pull --ff-only
    else
        git clone https://github.com/ldayton/Dippy.git "$dippy_dir"
    fi
}

# Step 8: Rust via rustup
install_rust() {
    if [ -x "$HOME/.cargo/bin/rustup" ]; then
        info "Rust already installed, skipping"
    else
        info "Installing Rust via rustup"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    fi
    # Source cargo env unconditionally so subsequent steps see cargo/rustup
    # (the rustup installer only adds these to interactive shells via .profile)
    # shellcheck disable=SC1091
    [ -s "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
}

# Step 9: tree-sitter CLI (needed by nvim-treesitter to compile parsers)
install_tree_sitter() {
    if command -v tree-sitter >/dev/null 2>&1; then
        info "tree-sitter-cli already installed, skipping"
    else
        info "Installing tree-sitter-cli via cargo"
        cargo install tree-sitter-cli
    fi
}

# Step 10: uv (Python package manager)
install_uv() {
    if command -v uv >/dev/null 2>&1; then
        info "uv already installed, skipping"
    else
        info "Installing uv"
        brew install uv
    fi
}

# Step 11: zoxide (smart cd)
install_zoxide() {
    if command -v zoxide >/dev/null 2>&1; then
        info "zoxide already installed, skipping"
    else
        info "Installing zoxide"
        brew install zoxide
    fi
}

# Step 11d: trash-cli — base_packages above already `brew install`s it, but
# the formula is keg-only on macOS (its bare `trash` command conflicts with
# macos-trash / osx-trash / trash formulae), so brew won't auto-link any of
# its binaries into $BREW_PREFIX/bin. Without symlinks the zshrc
# `alias rm="trash-put"` fails — `trash-put: command not found`.
#
# Link just the unique commands into ~/.local/bin/, skipping the conflicting
# bare `trash` so a future user could install macos-trash etc. without
# tripping over us.
install_trash_cli_links() {
    local keg_bin="$BREW_PREFIX/opt/trash-cli/bin"
    if [ ! -d "$keg_bin" ]; then
        info "trash-cli keg dir not found at $keg_bin; skipping link step"
        return
    fi
    info "Linking trash-cli commands into ~/.local/bin/"
    mkdir -p "$HOME/.local/bin"
    for cmd in trash-put trash-list trash-restore trash-empty trash-rm; do
        if [ -e "$keg_bin/$cmd" ]; then
            ln -sf "$keg_bin/$cmd" "$HOME/.local/bin/$cmd"
        fi
    done
}

# Step 11c: GitHub CLI. Installed via brew, then symlinked into ~/.local/bin/gh
# so the canonical path used elsewhere in dots (e.g. all/git/gitconfig's
# `helper = !~/.local/bin/gh auth git-credential`) resolves on macOS too —
# matching the Linux convention where the gh release tarball drops the binary
# under ~/.local/bin.
install_gh() {
    if command -v gh >/dev/null 2>&1; then
        info "gh already installed ($(gh --version | head -1))"
    else
        info "Installing GitHub CLI"
        brew install gh
    fi
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v gh)" "$HOME/.local/bin/gh"
}

# Step 11b: Google Sans Code Nerd Font (referenced by all/windows/wezterm.lua).
# Not in brew's cask repo; downloaded from a third-party prebuilt release.
install_nerd_font() {
    local font_dir="$HOME/Library/Fonts"
    if ls "$font_dir"/GoogleSansCodeNF*.ttf >/dev/null 2>&1; then
        info "Google Sans Code NF already installed, skipping"
        return
    fi
    info "Installing Google Sans Code Nerd Font"
    mkdir -p "$font_dir"

    local tmp
    tmp=$(mktemp -d)
    local zip_url="https://github.com/wylu1037/google-sans-code-nerd-font/releases/download/v1.0.0/google-sans-code-nerd-font.zip"
    curl -fsSL -o "$tmp/font.zip" "$zip_url"
    unzip -q "$tmp/font.zip" -d "$tmp/extracted"
    # zip layout isn't guaranteed; just collect any .ttf files anywhere inside
    find "$tmp/extracted" -name '*.ttf' -exec cp {} "$font_dir/" \;
    rm -rf "$tmp"

    # Strip the quarantine xattr that macOS sets on downloaded files —
    # CoreText silently skips quarantined font files when registering.
    xattr -d com.apple.quarantine "$font_dir"/GoogleSansCodeNF*.ttf 2>/dev/null || true

    # Purge the user font registry cache. Without this, apps that already saw
    # "no such font" (e.g. WezTerm on a prior launch) keep believing the font
    # is absent even after the file is registered.
    atsutil databases -remove >/dev/null 2>&1 || true
}

# Step 12: Oh-My-Zsh + plugins
install_ohmyzsh() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        info "Oh-My-Zsh already installed, skipping"
    else
        info "Installing Oh-My-Zsh"
        RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    fi

    local custom_plugins="$HOME/.oh-my-zsh/custom/plugins"

    if [ ! -d "$custom_plugins/fzf" ]; then
        info "Installing fzf oh-my-zsh plugin"
        git clone --depth 1 https://github.com/junegunn/fzf.git "$custom_plugins/fzf"
        "$custom_plugins/fzf/install" --bin
    else
        echo "fzf plugin already installed, skipping"
    fi

    if [ ! -d "$custom_plugins/fzf-zsh-plugin" ]; then
        info "Installing fzf-zsh-plugin"
        git clone --depth 1 https://github.com/unixorn/fzf-zsh-plugin.git "$custom_plugins/fzf-zsh-plugin"
    else
        echo "fzf-zsh-plugin already installed, skipping"
    fi

    if [ ! -d "$custom_plugins/zsh-uv-env" ]; then
        info "Installing zsh-uv-env"
        git clone --depth 1 https://github.com/matthiasha/zsh-uv-env.git "$custom_plugins/zsh-uv-env"
    else
        echo "zsh-uv-env already installed, skipping"
    fi
}

# Step 13: Dotfile configs via install.py
install_configs() {
    info "Installing dotfile configs via install.py"
    git -C "$DOTS_DIR" submodule update --init --recursive
    python3 "$DOTS_DIR/install.py" install configs
}

# Step 14: Fix oh-my-zsh directory permissions (compinit complains otherwise)
fix_permissions() {
    info "Fixing oh-my-zsh directory permissions"
    chmod -R 755 "$HOME/.oh-my-zsh/"
}

# Step 15: Neovim Python provider venv
install_nvim_venv() {
    if [ -d "$HOME/.virtualenvs/nvim" ]; then
        info "Neovim Python virtualenv already exists, skipping"
        return
    fi
    info "Creating Neovim Python virtualenv"
    mkdir -p "$HOME/.virtualenvs"
    python3 -m venv "$HOME/.virtualenvs/nvim"
    "$HOME/.virtualenvs/nvim/bin/pip" install pynvim
}

# Step 16: trash-cli TTL (auto-purge trashed files older than 30 days)
# Note: on macOS, cron jobs run via the legacy com.vix.cron LaunchDaemon and may
# require granting cron Full Disk Access (System Settings → Privacy & Security)
# before they can touch ~/.local/share/Trash.
setup_trash_ttl() {
    local cron_line="0 3 * * * trash-empty 30"
    if crontab -l 2>/dev/null | grep -qF "trash-empty"; then
        info "trash-empty cron already configured, skipping"
        return
    fi
    info "Adding daily trash-empty cron (30-day TTL)"
    if (crontab -l 2>/dev/null; echo "$cron_line") | crontab - 2>/dev/null; then
        return
    fi
    echo "Warning: 'crontab -' failed (macOS needs Full Disk Access for cron)."
    echo "  Grant: System Settings → Privacy & Security → Full Disk Access → /usr/sbin/cron"
    echo "  Then:  echo '$cron_line' | crontab -"
}

# Intentionally not translated from bootstrap-linux.sh:
#   - generate_locale            → macOS ships en_US.UTF-8 by default
#   - install_wsl_utils          → N/A
#   - install_docker             → install Docker Desktop / OrbStack / Colima
#                                  separately; out of scope here because choice
#                                  and licensing vary per user
#   - install_nvidia_container_toolkit → N/A

# Main
ensure_xcode_clt
install_homebrew
install_brew_packages
install_neovim
install_nvm_node
symlink_npmrc
install_ai_tools
install_rust
install_tree_sitter
install_uv
install_zoxide
install_gh
install_trash_cli_links
install_nerd_font
install_ohmyzsh
install_configs
fix_permissions
install_nvim_venv
setup_trash_ttl

info "Bootstrap complete!"
echo "To start using the brew zsh now:  exec $BREW_PREFIX/bin/zsh"
echo "To set it as your login shell:    sudo sh -c 'echo $BREW_PREFIX/bin/zsh >> /etc/shells' && chsh -s $BREW_PREFIX/bin/zsh"
