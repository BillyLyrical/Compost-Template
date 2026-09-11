# Compost Template Editor Support

Syntax highlighting and editor configuration for Compost templates.

## Vim

### Installation

1. Copy the syntax file to your Vim syntax directory:
```bash
cp editors/vim/syntax/compost.vim ~/.vim/syntax/
```

2. Copy the filetype detection file:
```bash
cp editors/vim/ftdetect/compost.vim ~/.vim/ftdetect/
```

Or install with Pathogen:
```bash
cd ~/.vim/bundle
git clone https://github.com/yourusername/compost-vim.git
```

### Usage

Vim will automatically detect `.tmpl` files as Compost templates.

To manually set the filetype:
```vim
:set filetype=compost
```

## Geany

### Installation

Run the install script:
```bash
cd editors/geany
chmod +x install.sh
./install.sh
```

Or manually:
```bash
cp editors/geany/filetypes.compost ~/.config/geany/filedefs/
```

### Usage

Restart Geany after installation. Files with `.tmpl` extension will be
automatically highlighted as Compost templates.

To manually set the filetype:
1. Go to Document > Set Filetype
2. Select "Compost Template"

## VS Code / Sublime Text

See the `syntaxes/` directory for TextMate grammar files.

## Supported Syntax

All editors highlight:
- Tags: `<% %>`, `<%- %>`, `<% +%>`, `<%- -%>`
- Keywords: if, elsif, else, unless, loop, switch, when, format, state
- Template tags: include, extends, block, super, macro, call, printf
- Variables: `$var`, `$var.name`, `$var.1.name`
- Magic variables: `$__count__`, `$__index__`, `$__line__`, etc.
- Strings: `"..."`, `'...'`
- Comments: `<% # comment %>`
- Operators: `=`, `!=`, `>`, `<`, `>=`, `<=`
- Scope prefixes: `$.var` (global), `$..var` (parent)
- Options: `-html`, `-url`, `-shrug`, `-global` (legacy alias for `$.var`)
- Dice notation: `2d6+1`, `4dX`
