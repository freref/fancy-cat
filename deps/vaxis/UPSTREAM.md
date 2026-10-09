# Vendored libvaxis

Source: https://github.com/rockorager/libvaxis
Commit: `7dbb9fd3122e4ffad262dd7c151d80d863b68558`
Original Zig package hash: `vaxis-0.5.1-BWNV_LosCQAGmCCNOLljCIw6j6-yt53tji6n6rwJ2BhS`
License: MIT (see LICENSE).

Local changes:

- `src/ctlseqs.zig`: use a valid 1x1 RGB Kitty capability query.
- `src/Parser.zig`: parse Kitty replies into image ID and OK/error status,
  instead of treating every graphics reply as successful capability detection.
- `src/event.zig`: add a graphics response event.
- `src/Vaxis.zig`: add an atomic acknowledgement slot.
- `src/Loop.zig`: publish acknowledgements and optionally forward response events.

Everything else is the unchanged pinned package. Vendoring keeps this change
reproducible without requiring an unpublished upstream API. Before merging,
maintainers may prefer to upstream these hooks and restore a URL/hash dependency.
