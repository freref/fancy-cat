# tmux 3.6 / Kitty graphics

Configure tmux (the application deliberately does not change server options):

```tmux
set -g allow-passthrough on
```

Run in the selected pane of a terminal implementing Kitty **Unicode placeholders**
(e.g. Kitty or Ghostty). Start with `fancy-cat document.pdf`.

## Implementation

`src/graphics/Tmux.zig` sends individual <=4096-byte base64 chunks in independent
DCS envelopes (`ESC P tmux;`, doubled inner ESCs, `ESC \\`). A real 1x1 RGB
query must receive an `OK`; environment variables alone never grant graphics
capability. The input parser preserves image IDs and positive/negative replies.
Transmit and virtual placement commands require acknowledgements and retry
losses around tmux redraws. Text, cursor movement and placeholder cells are
never passthrough wrapped.

Image IDs use indexed foreground colour plus a high-byte diacritic (65,280
randomised IDs), avoiding tmux truecolour downgrades. Placement ID 1 is bound via
underline colour. Row/column diacritics follow the Kitty protocol table, also
used in gominimal/kittyview. Glyph storage remains alive across vaxis frames.

Pixel geometry comes from TIOCGWINSZ; if missing, the outer client cell geometry
is queried from tmux, with an 8x16 fallback. Resize and PDF filewatch invalidate
rasterisation. The tmux backend does not use vaxis's direct-placement image cache;
it deletes replaced image data to avoid an unbounded terminal image store.

A 250ms visibility/focus tick handles hidden windows and detached clients.
Graphics transmissions are deferred while the pane is inactive: terminal replies
are routed by tmux to the active pane. Returning focus retransmits and redraws.
Existing placeholders in an inactive pane remain ordinary tmux text and repaint
with the client. Transient transmission/placement failures do not quit the app.
Following successful drawing, `tmux refresh-client` repairs the in-place
placeholder rendering issue in older Ghostty (see kittyview's slideshow backend).

## Verification performed

Zig 0.15.2 ReleaseSmall build; `zig build test`; real Ghostty 1.3.0-dev with tmux
3.6 in an isolated Xvfb display: first page, next page, window switch, horizontal
split, pane resize, PDF replacement while hidden, then return; screenshots and
red/blue/green pixel counts checked. Direct non-tmux rendering checked. Disabled
passthrough correctly fails the query rather than pretending graphics work.

## Boundaries

This backend targets one local tmux layer. Nested tmux/screen stacks are not
implemented. The outer terminal must implement Unicode placeholders, not merely
basic Kitty APC transmission. Start in the active attached pane so capability
replies return to this process. Graphics updates in inactive panes wait for focus.
Protocol row/column indices are limited to 297 cells. Multiple simultaneously
attached clients with independent image stores are not guaranteed; detach and
reattach to a single client is supported by retransmission. Physical Kitty and
macOS were not available for testing.

The patched libvaxis source is vendored in `deps/vaxis` from upstream commit
7dbb9fd3122e4ffad262dd7c151d80d863b68558, preserving its MIT license.
