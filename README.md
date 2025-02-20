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

### Configuration

fancy-cat can be configured through a JSON config file located at `~/.config/fancy-cat/config.json`. The file is automatically created on the first run with default settings.

The default `config.json` can be found [here](./src/config/config.json) and documentation on the config options can be found [here](./docs/config.md)

## Installation

### Arch Linux

fancy-cat is available as a package in the AUR ([link](https://aur.archlinux.org/packages/fancy-cat)). You can install it using an AUR helper (e.g., paru):

```sh
paru -S fancy-cat
```

## Build Instructions

### Requirements

- Zig version `0.13.0`
- Terminal emulator with the Kitty image protocol (e.g. Kitty, Ghostty, WezTerm, etc.)
- [MuPDF](https://mupdf.readthedocs.io/en/latest/quick-start-guide.html)

#### MacOS

```sh
brew install mupdf
```

#### Linux

```sh
apt install \
    libmupdf-dev \
    libharfbuzz-dev \
    libfreetype6-dev \
    libjbig2dec0-dev \
    libjpeg-dev \
    libopenjp2-7-dev \
    libgumbo-dev \
    libmujs-dev \
    zlib1g-dev
```

> [!IMPORTANT]  
> On some Linux distributions (e.g., Fedora, Arch), replace `mupdf-third` with `mupdf` in `build.zig` to compile successfully.

### Build

1. Fetch dependencies:

```sh
zig build --fetch
```

2. Build the project:

```sh
zig build --release=fast
```

> [!NOTE]
> There is a [known issue](https://github.com/freref/fancy-cat/issues/18) with some processors; if the build fails on step 7/10 with the error `LLVM ERROR: Do not know how to expand the result of this operator!` then try the command below instead:
>
> ```
> zig build --release=fast -Dcpu="skylake"
> ```

3. Install:

```
# Add to your PATH
# Linux
mv zig-out/bin/fancy-cat ~/.local/bin/

# macOS
mv zig-out/bin/fancy-cat /usr/local/bin/
```

### Run

```
zig build run -- <path-to-pdf> <optional-page-number>
```

## Features

- ✅ Filewatch (hot-reload)
- ✅ Custom keymapping
- ✅ Dark-mode
- ✅ Zoom
- ✅ Status bar
- 🚧 Cache
- 🚧 Search

## Contributing

Contributions are welcome.
