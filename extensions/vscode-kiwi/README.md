# kiwi

Minimal VS Code support for kiwi `.k` files.

## Features

- syntax highlighting for kiwi source
- distinct TextMate scopes for lambda braces (`{` and `}`)
- bundled `Kiwi Dark` and `Kiwi Light` color themes matching the Kiwi syntax palette
- one-space indentation defaults for `.k` files
- bracket and quote pairing, without backtick auto-close
- integrated-terminal REPL commands:
  - `kiwi: Start REPL`
  - `kiwi: Eval Selection or Current Statement`
  - `kiwi: Eval Current Block`
  - `kiwi: Eval File`
  - `kiwi: Reset Session`

## Keybindings

- `shift+enter`: eval selection or current statement
- `cmd+enter` on macOS / `ctrl+enter` elsewhere: eval current block
- `cmd+shift+enter` on macOS / `ctrl+shift+enter` elsewhere: eval file

## Settings

- `kiwi.binaryPath`: executable used to start the REPL, default `kiwi`
- `kiwi.replArgs`: extra arguments passed to the REPL command
- `kiwi.workingDirectory`: working directory for the REPL terminal
- `kiwi.environment`: environment variables for the REPL terminal

`shift+enter` sends the active selection when there is one. Without a selection,
it sends the smallest complete line-oriented statement around the cursor,
expanding across balanced `()`, `[]`, and `{}` while ignoring strings and
comments. `cmd+enter` / `ctrl+enter` sends the surrounding blank-line block and
expands it when needed to avoid cutting through a multiline statement.

The bundled `Kiwi Dark` and `Kiwi Light` themes apply the same token roles as
the web REPL and Apple apps. Other active VS Code themes can still style the
Kiwi grammar through the contributed TextMate scopes.
