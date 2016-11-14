" Vim syntax file
" " Language: Danet config syntax file
" " Maintainer: Vsevolod Svetlov
" " Latest Revision: 19 August 2016

if exists("b:current_syntax")
  finish
endif


syn match orange '^<[A-Za-z]\+>$'
syn match orange '^</[A-Za-z]\+>$'

syn match red '^ \+BatchSize '
syn match red '^ \+Name '

syn match blue '^ \+Type '
syn match blue '^ \+TrainDataPath '
syn match blue '^ \+ValidDataPath '

syn match green ' \+Ancestors '
syn match backend ' \+Backend'

syn match grey '//.\+'
syn match grey '#.\+'

let b:current_syntax = "danet-config"

hi def link orange Title
hi def link red Statement
hi def link blue Type
hi def link green PreProc
hi def link grey Comment

hi def link backend Constant
