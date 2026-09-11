" Vim syntax file
" Language:    Compost Template
" Maintainer:  Billy Lyrical <billy.lyrical@gmail.com>
" Filenames:   *.tmpl

if exists("b:current_syntax")
  finish
endif

" Tags
syn region compostTag matchgroup=compostTagDelimiter start=/<%[-+]\?/ end=/[-+]\?%>/ keepend contains=@compostTagContent

" Comment inside tag
syn match compostComment /#\s\?.\+/ contained

" Keywords
syn keyword compostKeyword if elsif else unless end loop switch when random dice format state ignore
syn keyword compostTagKeyword include extends block super macro call printf counter nop

" Variables
syn match compostVariable /\$\w\+\(\.\w\+\)*/ contained
syn match compostMagicVar /\$__\w\+__/ contained

" Strings
syn region compostStringDouble start=/"/ end=/"/ contained contains=compostVariable
syn region compostStringSingle start=/'/ end=/'/ contained

" Numbers
syn match compostNumber /\d\+/ contained
syn match compostDice /\d\+[dD]\w\+/ contained

" Operators
syn match compostOperator /!=\|[<>]=\?/[=!]=/ contained

" Options
syn match compostOption /-html\|-url\|-shrug\|-global/ contained

" Block delimiters
syn match compostBlockEnd /\/\w\+/ contained

" Highlighting
hi def link compostTagDelimiter Delimiter
hi def link compostComment Comment
hi def link compostKeyword Conditional
hi def link compostTagKeyword Function
hi def link compostVariable Identifier
hi def link compostMagicVar Special
hi def link compostStringDouble String
hi def link compostStringSingle String
hi def link compostNumber Number
hi def link compostDice Number
hi def link compostOperator Operator
hi def link compostOption Special
hi def link compostBlockEnd Keyword

let b:current_syntax = "compost"
