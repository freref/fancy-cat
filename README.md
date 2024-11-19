# fancy-cat
A PDF viewer for terminals using the Kitty image protocol.
![demo](https://github.com/user-attachments/assets/b1edc9d2-3b1f-437d-9b48-c196d22fcbbd) [^1]
[^1]: This demo shows me editing a Typst file that automatically compiles with each change, prompting fancy-cat to re-render whenever the PDF updates.
> [!NOTE]  
> This project is under active development
## Usage
The keymappings and other options can be found and changed in the config file [here](./src/config.zig).
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
```sh
zig build --fetch
```
### Run
```
zig build run -- <path-to-pdf> <optional-page-number>
```
## Features
- [x] Filewatch (hot-reload)
- [x] Custom keymapping
- [x] Dark-mode
- [x] Zoom
- [x] Status bar
- [ ] Cache
- [ ] Search
## Contributing
Contributions are welcome.
