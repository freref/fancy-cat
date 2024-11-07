# fancy-cat
A (blazingly-fast) PDF viewer for terminals using the Kitty image protocol (written in Zig).
![demo](https://github.com/user-attachments/assets/32393f0a-2cc3-438d-8c4e-870317714c2a)[^1]
[^1]: This demo shows me editing a Typst file that automatically compiles with each change, prompting fancy-cat to re-render whenever the PDF updates.
> [!NOTE]  
> This project is under active development
## Usage
The keymappings and other options can be found and changed in the config file [here](./src/config.zig).
## Build Instructions
### Requirements
- Terminal emulator with the Kitty image protocol (e.g. Kitty, WezTerm, Konsole, etc.)
- [mupdf](https://mupdf.readthedocs.io/en/latest/quick-start-guide.html)
#### MacOS
``` sh
brew install mupdf
```
#### Linux
``` sh
apt install mupdf
```
### Build
```sh
zig build --fetch
```
### Run
```
zig build run -- <path-to-pdf> <optional-page-number>
```
## Features
- [x] Filewatch
- [x] Navigate pages
- [x] Double buffering
- [x] MacOS support
- [ ] Linux support
- [ ] Zoom
- [ ] Ghostty support
- [ ] Cache
