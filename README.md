<h1>
<p align="center">
  📑
  <br>fancy-cat
</h1>
  <p align="center">
    PDF viewer for terminals using the Kitty image protocol
    <br />
  </p>
</p>

![demo](https://github.com/user-attachments/assets/b1edc9d2-3b1f-437d-9b48-c196d22fcbbd)

## Usage

```sh
fancy-cat <path-to-pdf> <optional-page-number>
```

### Commands

fancy-cat uses a modal interface similar to Neovim. There are two modes: view mode and command mode. To enter command mode you type `:` by default (this can be changed in the config file)

#### Available Commands

- `:<page-number>` - jump to the specified page number
- `:q` - quit the application

### Configuration

fancy-cat can be configured through a JSON config file located at `~/.config/fancy-cat/config.json`. The file is automatically created on the first run with default settings.

The default `config.json` can be found [here](./src/config/config.json) and documentation on the config options can be found [here](./docs/config.md)

## Installation

### Arch Linux

fancy-cat is available as a package in the AUR ([link](https://aur.archlinux.org/packages/fancy-cat)). You can install it using an AUR helper (e.g., paru):

```sh
paru -S fancy-cat
```

### Nix

Available as a Nix package [here](https://github.com/freref/fancy-cat-nix).

## Build Instructions

### Requirements

- Zig version `0.13.0`
- Terminal emulator with the Kitty image protocol (e.g. Kitty, Ghostty, WezTerm, etc.)

### Build

1. Fetch submodules:

```
git submodule update --init --recursive
```

2. Fetch dependencies:

```sh
zig build --fetch
```

3. Build the project:

```sh
zig build --release=small
```

> [!NOTE]
> There is a [known issue](https://github.com/freref/fancy-cat/issues/18) with some processors; if the build fails on step 7/10 with the error `LLVM ERROR: Do not know how to expand the result of this operator!` then try the command below instead:
>
> ```sh
> zig build -Dcpu="skylake" --release=small
> ```

4. Install:

```sh
# Add to your PATH
# Linux
mv zig-out/bin/fancy-cat ~/.local/bin/

# macOS
mv zig-out/bin/fancy-cat /usr/local/bin/
```

### Run

```sh
zig build run -- <path-to-pdf> <optional-page-number>
```

## Features

- ✅ Filewatch (hot-reload)
- ✅ Runtime config
- ✅ Custom keymappings
- ✅ Modal interface
- ✅ Commands
- ✅ Colorize mode (dark-mode)
- ✅ Page navigation (zoom, etc.)
- ✅ Status bar

## License

spdx-license-identifier: AGPL-3.0-or-later

## Contributing

Contributions are welcome.
