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
Keymappings and other options can be found and changed in ``src/config.zig``.
## Installation
### Arch Linux
[fancy-cat](https://aur.archlinux.org/packages/fancy-cat) is available as a package in the AUR. You can install it using an AUR helper (e.g., paru):
```sh
paru -S fancy-cat
```
## Build Instructions
### Requirements
- Zig version ``0.13.0``
- Terminal emulator with the Kitty image protocol (e.g. Kitty, Ghostty, WezTerm, etc.)
- [MuPDF](https://mupdf.readthedocs.io/en/latest/quick-start-guide.html)
#### MacOS
``` sh
brew install mupdf
```
#### Linux
``` sh
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
> On some Linux distributions (e.g., Fedora, Arch), replace `mupdf-third` with `mupdf` in ``build.zig`` to compile successfully.
### Build
1. Fetch dependencies:
```sh
zig build --fetch
```
2. Build the project:
```sh
zig build --release=fast
```
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
