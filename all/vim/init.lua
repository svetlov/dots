vim.g.mapleader = "\\"
vim.g.maplocalleader = "\\"

vim.cmd("filetype plugin indent on")  -- to fix proper filetype detection
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "--branch=stable",
    lazyrepo,
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)
vim.api.nvim_echo({ { "lazypath = " .. lazypath, "None" } }, false, {})
require("lazy").setup("plugins")

-- to prevent ^M symbol at the end of line when copy from windows to wsl
-- https://www.reddit.com/r/bashonubuntuonwindows/comments/1i0svwc/comment/mr8hbre/
vim.opt.clipboard = "unnamed,unnamedplus"
vim.g.clipboard = {
  name = 'WslClipboard',
  copy = {
    ['+'] = 'clip.exe',
    ['*'] = 'clip.exe',
  },
  paste = {
    ['+'] = 'powershell.exe -NoLogo -NoProfile -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
    ['*'] = 'powershell.exe -NoLogo -NoProfile -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
  },
  cache_enabled = 0,
}


-- =============================================================================
-- ================================= Keybindings ===============================
-- =============================================================================

-- =============================================================================
-- ================================= Global Settings ===========================
-- =============================================================================

-- allow to use external rc files
vim.o.exrc = true
-- restrict usage of some commands in external rc files
vim.o.secure = true

-- set syntax support if there's syntax file
vim.cmd.syntax("on")
-- add native colors for terminals except tty
vim.o.termguicolors = true

-- show the cursor position all the time
vim.o.ruler = true
-- Show line numbers
vim.o.number = true
-- Always show the statusline
vim.o.laststatus = 2
-- Highlight current line
vim.o.cursorline = true
-- color 120 characters in line
vim.wo.colorcolumn = "88"
-- Show matching brackets.
vim.o.showmatch = true

-- to convert every LF CR to LF eol
vim.o.fileformat = "unix"

-- Use spaces instead of tabs
vim.o.expandtab = true
vim.o.smarttab = true
-- always set autoindenting on
vim.o.smartindent = true
-- Width of a tab character
vim.o.tabstop = 4
-- Width for auto-indentation
vim.o.shiftwidth = 4
-- Width for tab/backspace operations
vim.o.softtabstop = 4

-- folding based on indent lvl
vim.o.foldmethod = "indent"
-- all folds open by default
vim.o.foldlevelstart = 99
-- Open splits to the right
vim.o.splitright = true

-- script encoding
vim.scriptencoding = "utf-8"
-- set encoding=utf-8
vim.o.encoding = "utf-8"
-- set fileencodings=utf-8,cp1251,koi8-r
vim.o.fileencodings = "utf-8,cp1251,koi8-r"
-- file mode is unix
vim.o.fileformat = "unix"
-- detects unix, dos, mac file formats in that order
vim.o.fileformats = "unix,dos,mac"

-- read/write file .viminfo, store<=500 lines of registers
vim.o.viminfo = [['20,"500]]
-- keep 200 lines of command line history
vim.o.history = 200

-- Suffixes that get lower priority when doing tab completion for filenames.
vim.o.suffixes = ".bak,~,.swp,.o,.info,.aux,.log,.dvi,.bbl,.blg,.brf,.cb,.ind,.idx,.ilg,.inx,.out,.toc"
-- for `gf' (open file under cursor)
vim.o.suffixesadd = ".pl,.pm,.yml,.yaml,.tyaml"

-- more native buffer behavior
vim.o.hidden = true

-- longer updatetime (default is 4000 ms) leads to noticeable delays
vim.o.updatetime = 300

-- Do case insensitive matching
vim.o.ignorecase = true
-- Incremental search
vim.o.incsearch = true
-- Highlight search
vim.o.hlsearch = true
-- Don't wrap around EOF or BOF while searching
vim.o.wrapscan = false

-- Automatically save before commands like :next and :make
-- vim.o.autowrite = true

-- When you type the first tab, it will complete as much as possible, the second
-- tab hit will provide a list, the third and subsequent tabs will cycle through
-- completion options so you can complete the file without further keys
vim.o.wildignore = "*/.git/*,*/.svn/*,*.o,*.so,*.pyc,*.whl"
vim.o.wildmode = "longest,full"
vim.o.wildmenu = true

-- The "longest" option makes completion insert the longest prefix of all
-- the possible matches; see :h completeopt
vim.o.completeopt = "menu,menuone,longest"
-- switchbuf=useopen,usetab
vim.o.switchbuf = "useopen,usetab"

-- Don't pass messages to |ins-completion-menu|.
vim.o.shortmess = vim.o.shortmess .. "c"

-- this makes sure that shell scripts are highlighted
-- as bash scripts and not sh scripts
vim.g.is_posix = 1

-- more powerful backspacing
vim.o.backspace = "indent,eol,start"

-- district directory for all swap files
vim.o.directory = vim.fn.expand("~/.vim/swap")
-- keep a backup file
vim.o.backupcopy = "yes"
-- use many levels of undo
vim.o.undolevels = 1000

-- Persistent undo
if vim.fn.has("persistent_undo") == 1 then
  vim.o.undofile = true
  -- undodir=~/.vim/undo
  vim.o.undodir = vim.fn.expand("~/.vim/undo")
end
