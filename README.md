# prismacat

`prismacat` is a tiny truecolor terminal cat with themeable gradients.

It reads text from files or stdin, paints it with a smooth ANSI 24-bit color gradient, and writes it back to stdout. Think `cat`, but refracted through your terminal theme collection instead of the default rainbow soup.

It is inspired by `lolcat`, but it is not trying to be a clone. No animation, no terminal theatrics, no 256-color fallback. Just fast themed truecolor output that composes well with normal Unix pipes.

```sh
fortune | cowsay | prismacat
prismacat README.md
prismacat --theme "Catppuccin Mocha" src/main.zig
prismacat --demo --spread 36
```

## Features

- Reads stdin, files, or `-` for stdin explicitly
- Always emits truecolor ANSI escape sequences
- 500+ generated themes from [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes)
- Case-insensitive theme lookup
- Configurable gradient spread
- Horizontal or diagonal gradients
- Build-time theme generation using Zig's package manager and build system

## Usage

```sh
prismacat [options] [FILE...]
```

With no files, `prismacat` reads stdin:

```sh
fortune | cowsay | prismacat
```

With files, it behaves like `cat` and processes each path in order:

```sh
prismacat file.txt another-file.txt
```

Use `-` to read stdin explicitly among file arguments:

```sh
printf 'hello from stdin\n' | prismacat intro.txt - outro.txt
```

Options:

```text
--theme NAME                  Select a theme
--spread CHARS, -s CHARS      Columns per full gradient cycle, default 50
--angle horizontal|diagonal   Gradient direction, default diagonal
--list-themes                 Print available themes
--demo                        Print sample art for every theme
--version, -v                 Print version
--help, -h                    Print usage
```

Theme names with spaces need shell quotes:

```sh
prismacat --theme "Rose Pine Moon" file.txt
prismacat --theme "Gruvbox Dark" file.txt
```

Theme lookup is case-insensitive:

```sh
prismacat --theme "catppuccin mocha" file.txt
```

## Themes

Themes are generated at build time from the Windows Terminal JSON exports in `mbadolato/iTerm2-Color-Schemes`. Each terminal scheme is converted into a gradient palette by extracting useful accent colors, filtering low-information grayscale-ish colors, deduplicating near matches, sorting by hue, and rotating the start point per theme.

That means themes are not just hardcoded rainbows with different names. They inherit the character of the source terminal scheme, then get shaped into something that works as a text gradient.

Useful discovery commands:

```sh
prismacat --list-themes
prismacat --demo | less -R
prismacat --demo --spread 80 | less -R
```

A few nice starting points:

```sh
prismacat --theme "12-bit Rainbow"
prismacat --theme "Catppuccin Mocha"
prismacat --theme "Gruvbox Dark"
prismacat --theme "Rose Pine Moon"
prismacat --theme "TokyoNight Night"
prismacat --theme "Adventure Time"
```

## Installation

### Homebrew

```sh
brew install --cask mattrobenolt/stuff/prismacat
```

## Building

This project targets Zig `0.16`.

```sh
zig build
zig build test
zig build run -- --demo
```

The theme repository is declared in `build.zig.zon`; Zig fetches package dependencies as needed. Generated theme Zig source is produced by build-time code in `src/build/themes.zig` and wired into the main module as `generated_themes`.

If you are using the provided Nix dev shell:

```sh
nix develop
zig build test
```

## Why

Because terminal colors are personal, and the default rainbow is not always the vibe.

Sometimes you want your cowsay fortune in Catppuccin. Sometimes you want logs in Gruvbox. Sometimes you want to preview 515 terminal themes by spraying ANSI escape codes into a pager like a responsible adult.

`prismacat` exists for that deeply important work.
