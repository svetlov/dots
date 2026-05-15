#!/usr/bin/env bash
set -euo pipefail

DOTS_DIR="$(dirname "$(readlink -f "$0")")"

info() {
    echo ""
    echo "==> $1"
    echo ""
}

# Step 1: Apt packages (hardcoded base + dynamic from ubuntu-deps.json)
install_apt_packages() {
    info "Installing apt packages"

    local base_packages=(
        zsh tmux git curl wget keychain lsb-release
        build-essential cmake unzip gettext
        software-properties-common
        ripgrep fd-find
        python3 python3-pip python3-venv
        imagemagick libmagickwand-dev luarocks
        libclang-dev
        jq
    )

    local dynamic_packages
    dynamic_packages=$(python3 -c "
import json, sys
print(' '.join(p['name'] for p in json.load(open(sys.argv[1]))['packages']))
" "$DOTS_DIR/all/code-agents/ubuntu-deps.json")

    sudo apt update
    # shellcheck disable=SC2086
    sudo apt install -y "${base_packages[@]}" $dynamic_packages
}

# Step 1b: WSL utilities (wslu) — only on WSL
install_wsl_utils() {
    if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] || \
       grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
        info "Installing WSL utilities (wslu)"
        sudo apt install -y wslu
    fi
}

# Step 2: Neovim from GitHub release
install_neovim() {
    local required_major=0
    local required_minor=11

    if command -v nvim &>/dev/null; then
        local ver
        ver=$(nvim --version | head -1 | grep -oP '\d+\.\d+')
        local major=${ver%%.*}
        local minor=${ver##*.}
        if [[ "$major" -gt "$required_major" ]] || [[ "$major" -eq "$required_major" && "$minor" -ge "$required_minor" ]]; then
            info "Neovim $ver already installed, skipping"
            return
        fi
        info "Neovim $ver is too old (need >= $required_major.$required_minor), upgrading"
    else
        info "Installing Neovim"
    fi

    local tmp
    tmp=$(mktemp -d)
    curl -Lo "$tmp/nvim.tar.gz" https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
    sudo tar -xzf "$tmp/nvim.tar.gz" -C /usr/local --strip-components=1
    rm -rf "$tmp"
}

# Step 3: Node.js via nvm
install_nvm_node() {
    if [ -d "$HOME/.nvm" ]; then
        info "nvm already installed, skipping"
    else
        info "Installing nvm"
        PROFILE=/dev/null bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash'
    fi

    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

    if ! command -v node &>/dev/null; then
        info "Installing Node.js LTS via nvm"
        nvm install --lts
    else
        info "Node.js already installed ($(node --version)), skipping"
    fi
}

# Step 4: Symlink npmrc early
symlink_npmrc() {
    info "Symlinking npmrc"
    ln -sf "$DOTS_DIR/all/zsh/npmrc" "$HOME/.npmrc"
}

# Step 5: AI CLI tools
install_ai_tools() {
    info "Installing AI CLI tools"

    if ! command -v claude &>/dev/null; then
        npm install -g @anthropic-ai/claude-code
    else
        echo "claude-code already installed, skipping"
    fi

    if ! command -v codex &>/dev/null; then
        npm install -g @openai/codex
    else
        echo "codex already installed, skipping"
    fi

    local dippy_dir="$HOME/.local/share/dippy"
    if [[ -d "$dippy_dir" ]]; then
        echo "dippy already installed, updating"
        git -C "$dippy_dir" pull --ff-only
    else
        git clone https://github.com/ldayton/Dippy.git "$dippy_dir"
    fi
}

# Step 6: Rust via rustup
install_rust() {
    if command -v rustup &>/dev/null; then
        info "Rust already installed, skipping"
    else
        info "Installing Rust via rustup"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        # shellcheck disable=SC1091
        source "$HOME/.cargo/env"
    fi
}

# Step 7: tree-sitter CLI (needed by nvim-treesitter to compile parsers)
install_tree_sitter() {
    if command -v tree-sitter &>/dev/null; then
        info "tree-sitter-cli already installed, skipping"
    else
        info "Installing tree-sitter-cli via cargo"
        cargo install tree-sitter-cli
    fi
}

# Step 8: uv (Python package manager)
install_uv() {
    if command -v uv &>/dev/null; then
        info "uv already installed, skipping"
    else
        info "Installing uv"
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
}

# Step 7b: zoxide (smart cd)
install_zoxide() {
    if command -v zoxide &>/dev/null; then
        info "zoxide already installed, skipping"
    else
        info "Installing zoxide"
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    fi
}

# Step 8: Docker Engine
install_docker() {
    if command -v docker &>/dev/null; then
        info "Docker already installed, skipping"
        return
    fi

    info "Installing Docker Engine"

    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo usermod -aG docker "$USER"
    sudo service docker start
}

# Step 8b: NVIDIA Container Toolkit (only if GPU is present)
install_nvidia_container_toolkit() {
    if ! command -v nvidia-smi &>/dev/null; then
        info "No NVIDIA GPU detected, skipping nvidia-container-toolkit"
        return
    fi

    if dpkg -l nvidia-container-toolkit &>/dev/null; then
        info "nvidia-container-toolkit already installed, skipping"
        return
    fi

    info "Installing NVIDIA Container Toolkit"

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
}

# Step 9: Oh-My-Zsh + plugins
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

# Step 7: Dotfile configs via install.py
install_configs() {
    info "Installing dotfile configs via install.py"
    git -C "$DOTS_DIR" submodule update --init --recursive
    python3 "$DOTS_DIR/install.py" install configs
}

# Step 8: Fix oh-my-zsh directory permissions
fix_permissions() {
    info "Fixing oh-my-zsh directory permissions"
    chmod -R 755 "$HOME/.oh-my-zsh/"
}

# Step 9b: trash-cli TTL (auto-purge trashed files older than 30 days)
setup_trash_ttl() {
    local cron_line="0 3 * * * trash-empty 30"
    if crontab -l 2>/dev/null | grep -qF "trash-empty"; then
        info "trash-empty cron already configured, skipping"
    else
        info "Adding daily trash-empty cron (30-day TTL)"
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
    fi
}

# Step 9c: Neovim Python virtualenv
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

# Step 10: Generate locale
generate_locale() {
    if locale -a 2>/dev/null | grep -q 'en_US.utf8'; then
        info "en_US.UTF-8 locale already exists, skipping"
    else
        info "Generating en_US.UTF-8 locale"
        sudo locale-gen en_US.UTF-8
    fi
}

# Main
generate_locale
install_apt_packages
install_wsl_utils
install_neovim
install_nvm_node
symlink_npmrc
install_ai_tools
install_rust
install_tree_sitter
install_uv
install_zoxide
install_docker
install_nvidia_container_toolkit
install_ohmyzsh
install_configs
fix_permissions
install_nvim_venv
setup_trash_ttl

info "Bootstrap complete!"
echo "To switch to zsh now:  exec zsh"
echo "To set zsh as default:  chsh -s \$(which zsh)"
