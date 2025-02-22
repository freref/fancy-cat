# Configuration

Configuration file location: `~/.config/fancy-cat/config.json`

## KeyMap

Each binding requires:

- `key`: `u8` (single character) - The main key to trigger the action
- `modifiers`: Array of strings - Optional modifier keys. Available modifiers:
  - `shift`
  - `alt`
  - `ctrl`
  - `super`
  - `hyper`
  - `meta`
  - `caps_lock`
  - `num_lock`

```jsonc
{
  "next": { "key": "n" },                           // Next page
  "prev": { "key": "p" },                           // Previous page
  "scroll_up": { "key": "k" },                      // Move viewport up
  "scroll_down": { "key": "j" },                    // Move viewport down
  "scroll_left": { "key": "h" },                    // Move viewport left
  "scroll_right": { "key": "l" },                   // Move viewport right
  "zoom_in": { "key": "i" },                        // Increase zoom level
  "zoom_out": { "key": "o" },                       // Decrease zoom level
  "colorize": { "key": "z" },                       // Toggle color inversion
  "quit": { "key": "c", "modifiers": ["ctrl"] }     // Exit program
}
```

## FileMonitor

Controls automatic reloading when PDF file changes. Useful for live previewing:

- `enabled`: `bool` - Toggle file change detection
- `latency`: `f16` - Time between file checks in seconds

## General

> [!NOTE]  
> fancy-cat uses color inversion for better terminal viewing. By default, it runs in dark mode where white pixels are displayed as black (0x000000) and black pixels as white (0xffffff). You can customize these colors to match your terminal theme - set white to your terminal's background color and black to your desired text.

- `colorize`: `bool` - Toggle color inversion for dark/light mode
- `white`: `i32` - Hex color code for white pixels in colorized mode
- `black`: `i32` - Hex color code for black pixels in colorized mode
- `size`: `f32` - PDF size relative to screen (0.0-1.0)
- `zoom_step`: `f32` - How much to zoom in/out per keystroke
- `zoom_min`: `f32` - Maximum zoom out level
- `scroll_step`: `f32` - Pixels to move per scroll command

## StatusBar

Configure the information bar at screen bottom:

- `enabled`: `bool` - Show/hide the status bar
- `style`: Status bar appearance
  - `bg`: Array of 3 `u8` values [r, g, b] - Text color (0-255)
  - `fg`: Array of 3 `u8` values [r, g, b] - Status bar color (0-255)
