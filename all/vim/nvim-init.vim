" =============================================================================
" ================================= Bundle Settings ===========================
" =============================================================================
set nocompatible              " be iMproved, required

filetype off                  " required by Vundle

silent! so .vimlocal          " add vimlocal for different projects

" install vim-plug if there is none
let b:vimplug_local_path = expand($HOME. '/.config/nvim/autoload/plug.vim')
let b:vimplug_remote_path = 'https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
if !filereadable(b:vimplug_local_path)
  echo "Installing vim-plug..\n"
  silent !mkdir -p ~/.config/nvim/plugged
  execute '!curl -fLo ' . b:vimplug_local_path . ' --create-dirs ' . b:vimplug_remote_path
endif


" Use different plugin directories based on context
if exists('g:vscode')
  call plug#begin(expand('~/.config/nvim/plugged-vscode'))
else
  call plug#begin(expand('~/.config/nvim/plugged'))
endif

Plug 'tpope/vim-commentary'

call plug#begin(expand('~/.config/nvim/plugged'))
if !exists('g:vscode')
    " ============================ UI section =====================================
    " impowed status line
    Plug 'bling/vim-airline'
    Plug 'vim-airline/vim-airline-themes'
    " color theme molokai
    Plug 'svetlov/molokai'
    " show ident blocks
    Plug 'Yggdroot/indentLine'
    " tmux and vim integration
    Plug 'christoomey/vim-tmux-navigator'
    " Project view
    " Plug 'preservim/nerdtree'
    " NERDTree plugin that highlights opened buffers
    Plug 'PhilRunninger/nerdtree-buffer-ops'

    " fast mru files navigation
    source $ZSH/custom/plugins/fzf/plugin/fzf.vim
    Plug 'junegunn/fzf'
    Plug 'junegunn/fzf.vim'

    " ===================== code-style section ====================================
    " python pep8 auto indent
    Plug 'hynek/vim-python-pep8-indent'
    " doxygen syntax highlight
    Plug 'vim-scripts/DoxyGen-Syntax'
endif

call plug#end()


if !exists('g:vscode')
    let g:python_host_prog='/usr/bin/python'
    let g:python3_host_prog='/usr/bin/python3'

    " =============================================================================
    " ============================= Airline Settings ==============================
    " =============================================================================

    set laststatus=2
    let g:airline_theme='solarized'
    if !exists('g:airline_symbols')
        let g:airline_symbols = {}
    endif

     let g:airline_theme = 'molokai'

    let g:airline_left_sep = '▶'
    let g:airline_right_sep = '◀'
    let g:airline_symbols.branch = '⎇'

    let g:airline#extensions#tabline#enabled = 1
    let g:airline#extensions#tabline#left_sep = ' '
    let g:airline#extensions#tabline#left_alt_sep = '|'

    " enable buffer indicies
    let g:airline#extensions#tabline#buffer_nr_show = 1
    " collapse buffer line if exactly one buffer
    let g:airline_inactive_collapse=1

    " =============================================================================
    " =============================== FZF Settings ================================
    " =============================================================================
    let g:fzf_layout = { 'down': '~25%' }
    let g:fzf_buffers_jump = 1

    " map <leader>p :FZF . <CR>
    " map <leader>P :FZF $ARCADIA_ROOT<CR>

    " Prevent FZF commands from opening in none modifiable buffers
    function! FZFOpen(cmd)
        " If more than 1 window, and buffer is not modifiable or file type is NERD tree or Quickfix type
        if winnr('$') > 1 && (!&modifiable || &ft == 'nerdtree' || &ft == 'qf')
            " Move one window to the right, then up
            wincmd l
            wincmd k
        endif
        exe a:cmd
    endfunction

    " FZF in Open buffers
    nnoremap <silent> <leader>b :call FZFOpen(":Buffers")<CR>

    " FZF Search for Files
    nnoremap <silent> <leader>f :call FZFOpen(":Files")<CR>

    " =============================================================================
    " ============================ NerdTree Settings ===========================
    " =============================================================================
    let g:NERDTreeWinSize = 80
    let g:NERDTreeBookmarksFile = $HOME.'/projects/dots/all/vim/NERDTreeBookmarks'
    let g:NERDTreeShowBookmarks = 1  "auto show bookmarks on enter
    let g:NERDTreeChDirMode = 2  " auto cd to bookmark directory
    let g:NERDTreeQuitOnOpen = 3  " Closes after opening a file and closes the bookmark table after opening a bookmark
    let g:NERDTreeRespectWildIgnore = 1

    " NERDTree setting defaults to work around http://github.com/scrooloose/nerdtree/issues/489
    let g:NERDTreeDirArrows = 1
    let g:NERDTreeDirArrowExpandable = '▸'
    let g:NERDTreeDirArrowCollapsible = '▾'
    let g:NERDTreeGlyphReadOnly = "RO"


    " =============================================================================
    " ================================ file switch ================================
    " =============================================================================

    let b:fsnonewfiles = "on"
    au BufEnter *.h let b:fswitchdst  = 'cpp,cc'
    au BufEnter *.h let b:fswitchlocs = 'rel:./'
    au BufEnter *.cc let b:fswitchdst  = 'h,hpp'
    au BufEnter *.cc let b:fswitchlocs = 'rel:./'
    nmap <silent> <leader>s :FSHere<CR>

    " =============================================================================
    " =============================== vim-commentry ===============================
    " =============================================================================
    autocmd FileType c,cpp setlocal commentstring=//\ %s

    " =============================================================================
    " ============================== Custom Functions =============================
    " =============================================================================

    function! Preserve(command)
        " Preparation: save last search, and cursor position.
        let _s=@/
        let l = line(".")
        let c = col(".")
        " Do the business:
        execute a:command
        " Clean up: restore previous search history, and cursor position
        let @/=_s
        call cursor(l, c)
    endfunction

    function! CallWithNormalizeSplits(command)
        execute a:command
        execute "wincmd ="
    endfunction

    " =============================================================================
    " ====================== Extentions KeyMap Settings ===========================
    " =============================================================================

    " danet config support
    au BufRead,BufNewFile *.cfg set filetype=danet-config

    " for ycm support of cuda
    autocmd FileType cuda set ft=cpp.cuda
    autocmd BufRead,BufNewFile *.cu set ft=cpp.cuda
    autocmd BufRead,BufNewFile *.cuh set ft=cpp.cuda

    " strip all trailing whitespaces at :w
    autocmd BufWritePre * :call Preserve("%s/\\s\\+$//e")
    " resize all splits if vim resized
    autocmd VimResized * wincmd =

    " Automatically close Quickfix window if it is the last one.
    aug QFClose
      au!
      au WinEnter * if winnr('$') == 1 && getbufvar(winbufnr(winnr()), "&buftype") == "quickfix"|q|endif
    aug END

    " go file in vertical split
    map gf :vertical wincmd f<CR>
    " auto reindent entire file
    nnoremap <silent> <C-E>ari :call Preserve("normal gg=G")<CR>

    colorscheme molokai                     " set my colorscheme
endif  " non-vscode section ends

" Detect .zshrc files as shell scripts
autocmd BufNewFile,BufRead .zshrc set filetype=sh
autocmd BufNewFile,BufRead *.zshrc set filetype=sh

"" =============================================================================
" ====================== Clipboard Settings ===================================
" =============================================================================

if exists('g:vscode')
  " VSCode Neovim: automatic clipboard integration
  if has("clipboard")
    if has("unnamedplus")
      set clipboard=unnamed,unnamedplus
    else
      set clipboard=unnamed
    endif
  endif
else
  " Auto-detect best clipboard method
  let s:is_remote = !empty($SSH_CLIENT) || !empty($SSH_CONNECTION)

  if has("clipboard") && !s:is_remote
    " Local Neovim with clipboard support
    if has("unnamedplus")
      set clipboard=unnamed,unnamedplus
    else
      set clipboard=unnamed
    endif
  else
    " Fallback: auto-copy on yank using appropriate method
    function! AutoCopyToClipboard()
      let @"=getreg('"')
      if s:is_remote
        " Remote: use OSC52 (works in most terminals)
        silent call system('printf "\033]52;c;'.base64_encode(@").'\033\\"')
      elseif executable('pbcopy')
        " macOS
        call system('pbcopy', @"")
      elseif executable('wl-copy')
        " Wayland
        call system('wl-copy', @"")
      elseif executable('xclip')
        " X11
        call system('xclip -selection clipboard', @"")
      elseif executable('xsel')
        " X11 fallback
        call system('xsel --clipboard --input', @"")
      endif
    endfunction

    augroup AutoClipboard
      au!
      au TextYankPost * call AutoCopyToClipboard()
    augroup END
  endif
endif

nnoremap S :%s/
vnoremap s :s/
nnoremap V <c-v>  " shift+v to enter visual mode

" =============================================================================
" ================================= Global Settings ===========================
" =============================================================================
set exrc                                " allow to use external rc files
set secure                              " restrict usage of some commands in external rc files

syntax on                               " set syntax support if there's syntax file
set t_Co=256                            " add native colors for terminals except tty

set ruler                               " show the cursor position all the time
set number                              " Show line numbers
set laststatus=2                        " Always show the statusline
set cursorline                          " Highlight current line
set colorcolumn=120                     " color 120 characters in line
" set showcmd                           " Show (partial) command in status line.
set showmatch                           " Show matching brackets.

set ff=unix                             " to convert every LF CR to LF eol

" Use spaces instead of tabs
set expandtab
set smarttab
set smartindent        " always set autoindenting on
set tabstop=4          " Width of a tab character
set shiftwidth=4       " Width for auto-indentation
set softtabstop=4      " Width for tab/backspace operations

set fdm=indent                          " folding based on indent lvl
set foldlevelstart=99                   " all folds open by default
set splitright                          " Open splits to the right

let g:load_doxygen_syntax = 1           " For doxygen syntax highlight
let g:python_highlight_all = 1          " For full python syntax highlight

scriptencoding utf-8
set encoding=utf-8
set fileencodings=utf-8,cp1251,koi8-r
set fileformat=unix                     " file mode is unix
set fileformats=unix,dos,mac            " detects unix, dos, mac file formats in that order

set viminfo='20,\"500                   " read/write file .viminfo, store<=500 lines of registers
set history=50                          " keep 50 lines of command line history

" Suffixes that get lower priority when doing tab completion for filenames.
set suffixes=.bak,~,.swp,.o,.info,.aux,.log,.dvi,.bbl,
	\.blg,.brf,.cb,.ind,.idx,.ilg,.inx,.out,.toc
" for `gf' (open file under cursor)
set suffixesadd=.pl,.pm,.yml,.yaml,.tyaml

set hidden                              " more native buffer behavior
set undolevels=1000                     " use many levels of undo


set updatetime=300                      " longer updatetime (default is 4000 ms) leads to noticeable delays

set ignorecase                          " Do case insensitive matching
set incsearch                           " Incremental search
set hlsearch                            " Highlight search
set nowrapscan                          " Don't wrap around EOF or BOF while searching


" set autowrite                         " Automatically save before commands like :next and :make

" When you type the first tab, it will complete as much as possible, the second
" tab hit will provide a list, the third and subsequent tabs will cycle through
" completion options so you can complete the file without further keys
set wildignore=*/.git/*,*/.svn/*
set wildignore+=*.o,*.so,*.pyc
set wildignore+=*.whl
set wildmode=longest,full
set wildmenu

" The "longest" option makes completion insert the longest prefix of all
" the possible matches; see :h completeopt
set completeopt=menu,menuone,longest
set switchbuf=useopen,usetab

set shortmess+=c                        " Don't pass messages to |ins-completion-menu|.

" this makes sure that shell scripts are highlighted
" as bash scripts and not sh scripts
let g:is_posix = 1

set backspace=indent,eol,start	" more powerful backspacing
set dir=~/.vim/swap   " district directory for all swap files
set backupcopy=yes " keep a backup file
if has("persistent_undo")
  set undofile    " Persistent  undo
  set undodir=~/.vim/undo
endif  " has("persistent_undo")
