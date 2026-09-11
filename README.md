# Compost::Template v0.5.2

A Perl templating engine. Originally written in 2005, updated and
modernized for current Perl (5.14+).

Templates are compiled to a simple bytecode format for fast interpretation.
Useful for web templating, text generation, or any job that benefits from
a clean template syntax.

## Overview

Compost::Template is a pre-compiled bytecode template engine for Perl.
Templates are compiled to a flat instruction array, cached to disk,
and interpreted at runtime. The design prioritizes three things:

| | |
|---|---|
| **Speed** | compile once, run many; no parsing at runtime |
| **Safety** | sandboxed execution; no arbitrary Perl in templates |
| **Simplicity** | minimal surface area; easy to audit and extend |

The engine has two phases:

```
Template Text → [Parser.pm] → Bytecode Array
                                     ↓
                                 [Cache] ← serialize to disk
                                     ↓
Output String ← [Runtime.pm] ← Bytecode Array
```

These phases are completely separated. A compiled template can be
cached and reused across requests without re-parsing.

## Features

- `<% if %>` / `<% elsif %>` / `<% else %>` / `<% unless %>`
- `<% loop $list %>` with `__count__`, `__index__`, `__total__`, `__first__`, `__last__`, `__inner__`, `__outer__`, `__even__`, `__odd__`
- `<% random $list %>` picks a random item from a list
- `<% dice 2d6+1 %>` rolls dice (`NdS+/-M`) or letter dice (`NdB`, `NdX`, `ndx`, `NdA`, `nda`)
- `<% switch %>` / `<% when %>`
- `<% map $hash %>` over hashes or arrays
- `<% printf "%08d" $var %>` for padding and formatting
- `<% format upper %>` / `ucfirst` / `lcfirst` / `capitalize` / `reverse` / `repeat` / `center` / `slugify` / `strip_tags` / `truncate_words` / `truncate` / `trim` / `wordwrap` / `text2html`
- `<% $var | filter %>` pipe syntax for chaining filters
- `<% extends base.tmpl %>` / `<% block name %>` / `<% super %>` for template inheritance
- `<% macro name($params) %>` / `<% call name $args %>` for reusable macros
- `<% call $callback $arg %>` for Perl callbacks
- `<% state Key pattern %>` for regex-matchable state
- `<% $var or $fallback %>` for default values
- Scope chains: `<% $var %>` (local), `<% $.var %>` (global), `<% $..var %>` (parent)
- `<% $__line__ %>` / `<% $__file__ %>` / `<% $__time__ %>` / `<% $__user__ %>` / `<% $__version__ %>`
- Whitespace control with `+%>` and `-%>`
- Template includes with recursion protection
- Compiled bytecode cache for performance
- Line-number error reporting
- HTML and URL escaping

## Quick Start

```perl
use Compost::Template;

my $template = Compost::Template->new( filename => 'test.tmpl' );
$template->param(
    name => 'Steve',
    age  => 34,
);
print $template->run;
```

Given `test.tmpl`:

```
My name is <% $name %>,
I am <% $age %> years old.
```

Output:

```
My name is Steve,
I am 34 years old.
```

## Installation

```sh
perl Makefile.PL
make
make test
make install
```

## Dependencies

- **Runtime:** `File::Spec`, `Path::Tiny`
- **Test-only:** `Test::More`

## Documentation

```sh
perldoc Compost::Template
```

## Bug Reports

Email: billy.lyrical@gmail.com

## License

Licensed under the same terms as Perl itself (GPL v1+ or Artistic License 1).

Copyright (C) 2007-2026 Billy Lyrical <billy.lyrical@gmail.com>
