# Compost Template Syntax Highlighting

TextMate grammar for Compost templates (`.tmpl` files).

## Installation

### VS Code

1. Copy `compost.tmLanguage.json` to your VS Code extensions directory:
   - Linux: `~/.vscode/extensions/compost-template/syntaxes/`
   - macOS: `~/.vscode/extensions/compost-template/syntaxes/`
   - Windows: `%USERPROFILE%\.vscode\extensions\compost-template\syntaxes\`

2. Create `~/.vscode/extensions/compost-template/package.json`:
```json
{
  "name": "compost-template",
  "displayName": "Compost Template Syntax",
  "description": "Syntax highlighting for Compost templates",
  "version": "0.1.0",
  "engines": { "vscode": "^1.0.0" },
  "contributes": {
    "languages": [{
      "id": "compost",
      "aliases": ["Compost Template", "compost"],
      "extensions": [".tmpl"],
      "configuration": "./language-configuration.json"
    }],
    "grammars": [{
      "language": "compost",
      "scopeName": "source.compost",
      "path": "./syntaxes/compost.tmLanguage.json"
    }]
  }
}
```

3. Create `~/.vscode/extensions/compost-template/language-configuration.json`:
```json
{
  "comments": { "blockComment": ["<%#", "%>"] },
  "brackets": [["<%", "%>"]],
  "autoClosingPairs": [
    { "open": "<%", "close": "%>" },
    { "open": "\"", "close": "\"" },
    { "open": "'", "close": "'" }
  ]
}
```

### Sublime Text

1. Copy `compost.tmLanguage.json` to your Sublime Text Packages directory:
   - Linux: `~/.config/sublime-text/Packages/Compost/`
   - macOS: `~/Library/Application Support/Sublime Text/Packages/Compost/`
   - Windows: `%APPDATA%\Sublime Text\Packages\Compost\`

2. Rename the file to `Compost.tmLanguage`

### Other Editors

The grammar file follows the TextMate format and can be adapted for:
- Atom (uses TextMate grammars)
- Emacs (via `editorconfig` or `web-mode`)
- Vim (via `vim-tmux` or custom syntax file)

## Supported Syntax

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
