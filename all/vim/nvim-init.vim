" =============================================================================
" ================================= Bundle Settings ===========================
" =============================================================================
set nocompatible              " be iMproved, required
filetype off                  " required by Vundle

silent! so .vimlocal          " add vimlocal for different projects

" install Vindle if there is none
if !filereadable(expand('$HOME/.config/nvim/bundle/Vundle.vim/README.md'))
    echo "Installing Vundle.."
    echo ""
    silent !mkdir -p ~/.vim/bundle
    silent !git clone --quiet https://github.com/gmarik/Vundle.vim ~/.config/nvim/bundle/Vundle.vim
endif

" set the runtime path to include Vundle and initialize
set rtp+=~/.config/nvim/bundle/Vundle.vim
call vundle#begin("~/.config/nvim/bundle")

" let Vundle manage Vundle, required
Plugin 'gmarik/Vundle.vim'

" ============================ UI section =====================================
" impowed status line
Plugin 'bling/vim-airline'
Plugin 'vim-airline/vim-airline-themes'
" color theme molokai
Plugin 'svetlov/molokai'
" tmux and vim integration
Plugin 'christoomey/vim-tmux-navigator'
" buffer navigator like nerdtree
Plugin 'jeetsukumaran/vim-buffergator'

" ===================== code-style section ====================================
" easy comment for common languages
Plugin 'tpope/vim-commentary'
" python pep8 auto indent
Plugin 'hynek/vim-python-pep8-indent'
" doxygen syntax highlight
Plugin 'vim-scripts/DoxyGen-Syntax'

" ========================== dev section ======================================
" fast switch of header and source c/cpp files
Plugin 'derekwyatt/vim-fswitch'
" code autocomplete for c/c++/python
Plugin 'Valloric/YouCompleteMe'
" snippets plugin
Plugin 'SirVer/ultisnips'
" Snippets are separated from the plugin.
Plugin 'honza/vim-snippets'

call vundle#end()             " reguired by Vundle
filetype plugin indent on     " required by Vundle

" Do things a bit different if we are at Yandex
let arcadia_root = $ARCADIA_ROOT . '/'
if arcadia_root != '/'
    let &path.=',' . arcadia_root
    let yandex_config_path = string(arcadia_root) . 'junk' . 'splinter' . 'vimrc'
    if filereadable(yandex_config_path)
        exec 'source ' . yandex_config_path
    endif
endif

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
" ============================= UltiSnips Settings ============================
" =============================================================================

" set rtp+=~/projects/dots/all/vim/  " for mysnippets directory
let g:UltiSnipsExpandTrigger = "<C-j>"
let g:UltiSnipsEditSplit = 'vertical'
let g:UltiSnipsSnippetDirectories=[$HOME.'/projects/dots/all/vim/mysnippets', "UltiSnips"]

" =============================================================================
" ============================ Buffergator Settings ===========================
" =============================================================================

let g:buffergator_hsplit_size = 20
let g:buffergator_viewport_split_policy="B"  " open at top

let g:buffergator_suppress_keymaps = 1
map <leader>b :BuffergatorToggle<CR>

" =============================================================================
" ================================ YCM Settings ===============================
" =============================================================================
let g:ycm_confirm_extra_conf = 0
let g:ycm_add_preview_to_completeopt = 1
let g:ycm_global_ycm_extra_conf = $HOME . '/projects/dots/all/vim/ycm.py'
let g:ycm_goto_buffer_command = 'vertical-split'
let g:ycm_autoclose_preview_window_after_completion = 1
let g:ycm_autoclose_preview_window_after_insertion = 1

let g:ycm_python_binary_path = 'python'

let g:ycm_error_symbol = '☓'
let g:ycm_warning_symbol = '☝'
let g:ycm_filetype_specific_completion_to_disable = {
    \ 'csv' : 1,
    \ 'gitcommit' : 1,
    \ 'diff' : 1,
    \ 'help' : 1,
    \ 'infolog' : 1,
    \ 'mail' : 1,
    \ 'markdown' : 1,
    \ 'notes' : 1,
    \ 'pandoc' : 1,
    \ 'qf' : 1,
    \ 'svn' : 1,
    \ 'tagbar' : 1,
    \ 'text' : 1,
    \ 'unite' : 1,
    \ 'vimwiki' : 1
    \}

let g:ycm_key_list_select_completion = ['<Down>']
let g:ycm_key_list_previous_completion = ['<Up>']

map gdf :YcmComplete GoToDefinition<CR>
map gdc :YcmComplete GoToDeclaration<CR>
autocmd FileType c,ccp nnoremap <buffer> gdh :YcmCompleter GetDoc<CR>
" " for auto ident one symbol at left in case of errors
" autocmd BufEnter * sign define dummy
" autocmd BufEnter * execute 'sign place 9999 line=1 name=dummy buffer=' . bufnr('')

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

function! CallWithNormalizeSplints(command)
    execute a:command
    execute "wincmd ="
endfunction

function! PropagatePasteBufferToOSX()
  let @n=getreg('"')
  call system('pbcopy', @n)
  echo "done"
endfunction

function! PopulatePasteBufferFromOSX()
  let @"=system('pbpaste')
  echo "done"
endfunction

" =============================================================================
" ================================= KeyMap Settings ===========================
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

" copy/paste buffers manipulating with localhost
nnoremap <C-E>p :call PopulatePasteBufferFromOSX()<cr>
nnoremap <C-E>y :call PropagatePasteBufferToOSX()<cr>

nnoremap S :%s/
vnoremap s :s/

nnoremap <C-M> :MaximizerToggle<CR>

" =============================================================================
" ================================= Global Settings ===========================
" =============================================================================
set exrc                                " allow to use external rc files
set secure                              " restrict usage of some commands in external rc files

syntax on                               " set syntax support if there's syntax file
set t_Co=256                            " add native colors for terminals except tty
colorscheme molokai                     " set my colorscheme

set ruler                               " show the cursor position all the time
set number                              " Show line numbers
set laststatus=2                        " Always show the statusline
set cursorline                          " Highlight current line
set colorcolumn=120                     " color 120 characters in line
" set showcmd                           " Show (partial) command in status line.
set showmatch                           " Show matching brackets.

set shiftwidth=4
set tabstop=4
set softtabstop=4
set smartindent                         " always set autoindenting on
set smarttab
set expandtab

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

set ignorecase                          " Do case insensitive matching
set incsearch                           " Incremental search
set hlsearch	                        " Highlight search
set nowrapscan	                        " Don't wrap around EOF or BOF while searching

" set autowrite                         " Automatically save before commands like :next and :make

" When you type the first tab, it will complete as much as possible, the second
" tab hit will provide a list, the third and subsequent tabs will cycle through
" completion options so you can complete the file without further keys
set wildignore=*/.git/*,*/.svn/*
set wildignore+=*.o,*.so,*.pyc
set wildmode=longest,full
set wildmenu

" The "longest" option makes completion insert the longest prefix of all
" the possible matches; see :h completeopt
set completeopt=menu,menuone,longest
set switchbuf=useopen,usetab

" this makes sure that shell scripts are highlighted
" as bash scripts and not sh scripts
let g:is_posix = 1

set backspace=indent,eol,start	" more powerful backspacing
set dir=~/.vim/swap   " district directory for all swap files
set backupcopy=yes " keep a backup file
if has("persistent_undo")
    set undofile    " Persistent  undo
    set undodir=~/.vim/undo
endif
