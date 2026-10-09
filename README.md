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

fancy-cat uses a modal interface similar to Neovim. There are two modes: view mode and command mode. To enter command mode you type `:` by default (this can be changed in the config file).

Documentation on the available commands can be found [here](./docs/commands.md).

### Configuration

fancy-cat can be configured through a JSON configuration file located in one of several locations (primary `$XDG_CONFIG_HOME/fancy-cat/config.json`, fallback `$HOME/.config/fancy-cat/config.json`, legacy `$HOME/.fancy-cat`). An empty configuration file is automatically created in the primary or fallback location on the first run.

An example `config.json` and documentation can be found [here](./docs/config.md).

## tmux

For tmux 3.6, enable `set -g allow-passthrough on` and use a terminal with
Kitty Unicode placeholder support. See [tmux backend and verification](docs/tmux.md).

## Installation

`fancy-cat` is available in the following repositories:

[![Packaging status](https://repology.org/badge/vertical-allrepos/fancy-cat.svg?columns=3&header=fancy-cat)](https://repology.org/project/fancy-cat/versions)

## Build Instructions

### Requirements

- Zig version `0.15.2`
- Terminal emulator with the Kitty image protocol (e.g. Kitty, Ghostty, WezTerm, etc.)

### Build

1. Fetch submodules:

```
git submodule update --init --recursive
```

2. Build the project:

```sh
zig build --release=small
```

> [!NOTE]
> There is a [known issue](https://github.com/freref/fancy-cat/issues/18) with some processors; if the build fails on step 7/10 with the error `LLVM ERROR: Do not know how to expand the result of this operator!` then try the command below instead:
>
> ```sh
> zig build -Dcpu="skylake" --release=small
> ```

3. Install:

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
- ✅ Status bar
- ✅ Page navigation (zoom, prev, next, etc.)

## License

[AGPL-3.0-or-later](https://spdx.org/licenses/AGPL-3.0-or-later.html)

## Contributing

Contributions are welcome.
