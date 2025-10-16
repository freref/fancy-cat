# Configuration

On startup, fancy-cat looks for a configuration file at:

```
~/.config/fancy-cat/config.json
```

If no configuration file is found, fancy-cat creates an empty one. Since fancy-cat comes with sensible defaults, you only need to add the options you want to change.

## Defaults

Below is an example configuration file that replicates the default settings. You can use it as a starting point for your customizations:

```json
{
  "KeyMap": {
    "next": { "key": "n" },
    "prev": { "key": "p" },
    "scroll_up": { "key": "k" },
    "scroll_down": { "key": "j" },
    "scroll_left": { "key": "h" },
    "scroll_right": { "key": "l" },
    "zoom_in": { "key": "i" },
    "zoom_out": { "key": "o" },
    "width_mode": { "key": "w" },
    "colorize": { "key": "z" },
    "quit": { "key": "c", "modifiers": [ "ctrl" ] },
    "enter_command_mode": { "key": ":" },
    "exit_command_mode": { "key": "escape" },
    "execute_command": { "key": "enter" }
  },
  "FileMonitor": {
    "enabled": true,
    "latency": 0.1,
    "reload_indicator_duration": 1.0
  },
  "General": {
    "colorize": false,
    "white": "#000000",
    "black": "#ffffff",
    "size": 1.0,
    "zoom_step": 1.25,
    "zoom_min": 1.0,
    "scroll_step": 100.0,
    "retry_delay": 0.2,
    "timeout": 5.0,
    "dpi": 96.0
  },
  "StatusBar": {
    "enabled": true,
    "style": { "bg": "#000000", "fg": "#ffffff" },
    "items": [
      " ",
      { "view": { "text": "VIS" }, "command": { "text": "CMD" } },
      "   <path> ",
      { "idle": { "text": " " }, "reload": { "text": "*" } }, 
      "<separator><page>:<total_pages> "
    ]
  },
  "Cache": {
    "enabled": true,
    "lru_size": 10
  }
}
```

The rest of this reference provides detailed explanations for each configuration section. 

## Contents

- [Key Map](#key-map)
  - [Keybindings](#keybindings)
    - [Keys](#keys)
    - [Modifiers](#modifiers)
- [File Monitor](#file-monitor)
- [General](#general)
  - [Color](#color)
- [Status Bar](#status-bar)
  - [Style](#style)
    - [Underline](#underline)
  - [Items](#items)
    - [Plain Items](#plain-items)
    - [Styled Items](#styled-items)
    - [Mode-aware Items](#mode-aware-items)
     - [Reload-aware Items](#reload-aware-items)
- [Cache](#cache)

---

## Key Map

The `KeyMap` section defines keybindings for various actions.

| Action | Description |
| :--- | :--- |
| `next` | Go to the next page |
| `prev` | Go to the previous page |
| `scroll_up` | Move the viewport up |
| `scroll_down` | Move the viewport down |
| `scroll_left` | Move the viewport left |
| `scroll_right` | Move the viewport right |
| `zoom_in` | Increase the zoom level |
| `zoom_out` | Decrease the zoom level |
| `width_mode` | Toggle between full-height or full-width mode |
| `colorize` | Toggle color replacement |
| `quit` | Exit the program |
| `enter_command_mode` | Enter command mode |
| `exit_command_mode` | Exit command mode |
| `execute_command` | Execute the entered command |

### Keybindings

Each keybinding is an object named after the action it performs. This object includes:

| Property | Type | Description |
| :--- | :--- | :--- |
| `key` | [Key](#keys) | The key that triggers the action |
| `modifiers` (optional) | [Modifiers](#modifiers) | Other keys that must be held down to trigger the action |

#### Keys

The `key` property can be set to either a single character (like `a`, `1`, or `:`) or one of the following keys:

| Key | Description |
| :--- | :--- |
| `escape` | Escape key |
| `enter` | Enter (Return) key |
| `space` | Space bar |
| `tab` | Tab key |
| `backspace` | Backspace key |
| `delete` | Delete key |
| `insert` | Insert key |
| `home` | Home key |
| `end` | End key |
| `page_up` | Page Up key |
| `page_down` | Page Down key |
| `up` | Up arrow key |
| `down` | Down arrow key |
| `left` | Left arrow key |
| `right` | Right arrow key |
| `f1`–`f12` | Function keys |

> [!NOTE]
> This reference includes the most commonly used keys. The [complete list](https://github.com/rockorager/libvaxis/blob/main/src/Key.zig) is more extensive, though support may vary by terminal or keyboard.

#### Modifiers

The `modifiers` property can be set to an array that includes any combination of the following keys:

| Modifier | Description |
| :--- | :--- |
| `shift` | Shift key |
| `alt` | Alt (Option) key |
| `ctrl` | Control key |
| `super` | Super (Windows or Command) key |
| `hyper` | An advanced modifier key |
| `meta` | Another advanced modifier key |
| `caps_lock` | Caps Lock key |
| `num_lock` | Num Lock key |

---

## File Monitor

The `FileMonitor` section controls the automatic reloading feature, useful for live previews.

| Property | Type | Description |
| :--- | :--- | :--- |
| `enabled` | Boolean | Enables file change detection and automatic reloading |
| `latency` | Float (seconds) | The time interval between checking for changes |
| `reload_indicator_duration` | Float (seconds) | How long the reload indicator remains visible (`0.0` disables it) |

---

## General

The `General` section includes various display and timing settings.

| Property | Type | Description |
| :--- | :--- | :--- |
| `colorize` | Boolean | Enables color replacement on startup |
| `white` | [Color](#color) | Replacement color for white |
| `black` | [Color](#color) | Replacement color for black |
| `size` | Float | Initial zoom level multiplier (`1.0` fits the full height) |
| `zoom_step` | Float | Zoom multiplier per keystroke |
| `zoom_min` | Float | Minimum zoom level allowed |
| `scroll_step` | Float (pixels) | Distance the viewport moves per scroll keystroke |
| `dpi` | Float | Resolution used for 100% zoom calculation |
| `retry_delay` | Float (seconds) | Delay before retrying to load a document or render a page |
| `timeout` | Float (seconds) | Maximum time to keep retrying before giving up on loading a document or rendering a page |

>[!TIP]
>The color replacement feature works by replacing white and black with custom colors, which also affects the full color range depending on contrast. By default, `white` is set to black (`#000000`) and `black` is set to white (`#ffffff`). For a seamless look, try setting `white` to match your terminal’s background color and `black` to match the foreground (text) color.

### Color

The following color formats are supported:

| Format  | Description |
| :---  | :--- |
| `"#RRGGBB"` or `"0xRRGGBB"` | `RR`, `GG`, and `BB` are two-digit hexadecimal values |
| `{ "rgb": [R, G, B] }` | `R`, `G`, and `B` are integers between 0 and 255 |

---

## Status Bar

The `StatusBar` section controls the information shown at the bottom of the window.

| Property | Type | Description |
| :--- | :--- |  :--- |
| `enabled` | Boolean | Enables the status bar |
| `style` | [Style](#style) | Default appearance of the entire status bar |
| `items` | [Items](#items) | Status bar items |

### Style

A `style` object can include the following properties:

| Property | Type | Description |
| :--- | :--- | :--- |
| `fg` | [Color](#color) | Foreground (text) color |
| `bg` | [Color](#color) | Background color |
| `ul` | [Color](#color) | Underline color |
| `bold` | Boolean | Bold text |
| `italic` | Boolean | Italic text |
| `ul_style` | [Underline](#underline) | Underline style |

>[!NOTE]
>This reference provides the most commonly used style properties. The [complete list](https://github.com/rockorager/libvaxis/blob/main/src/Cell.zig) includes others, though support may vary by terminal.

#### Underline

The `ul_style` property can be set to one of the following styles:

| Style | Description |
| :--- | :--- |
| `off` | No underline |
| `single` | Single underline |
| `double` | Double underline |
| `curly` | Curly underline |
| `dotted` | Dotted underline |
| `dashed` | Dashed underline |

### Items

The `items` property can be set to an array of status bar items, which include:

* **[plain items](#plain-items)**: text with default styling
* **[styled items](#styled-items)**: text with custom [styling](#style)
* **[mode-aware items](#mode-aware-items)**: styled items to be displayed depending on the current mode
* **[reload-aware items](#reload-aware-items)**: styled items to be displayed depending on the current reload indicator state
#### Plain Items

Plain items are just strings that may include placeholders (e.g., `<page>:<total_pages>`). These placeholders are replaced with dynamic content at runtime.

| Placeholder | Description |
| :--- | :--- |
| `<path>` | The file path |
| `<page>` | The current page number |
| `<total_pages>` | The total number of pages |
| `<separator>` | Inserts a space to separate the left and right sides of the status bar |

#### Styled Items

Each styled item is an object containing:

| Property | Type | Description |
| :--- | :--- | :--- |
| `text` | [Plain item](#plain-items) | Text to display |
| `style` (optional) | [Style](#style) | Overrides the default appearance |

**Example:** Underline the file path with a single green line:

```json
{ "text": "<path>", "style": { "ul": "#00ff00", "ul_style": "single" } }
```
>[!NOTE]
>If no style is provided, a styled item behaves just like a plain item.

#### Mode-aware Items

Mode-aware items switch their content based on the current mode. Each item must include at least one of:

| Property | Type | Description |
| :--- | :--- | :--- |
| `view` | [Styled item](#styled-items) | Item to display in view mode |
| `command` | [Styled item](#styled-items) | Item to display in command mode |

**Example:** Display a bold red "VIS" in view mode and a bold blue "CMD" in command mode:

```json
{
  "view": { "text": "VIS", "style": { "fg": "#ff0000", "bold": true } },
  "command": { "text": "CMD", "style": { "fg": "#0000ff", "bold": true } }
}
```

#### Reload-aware Items

Reload-aware items switch their content based on the reload indicator state. Each item must include at least one of:

| Property | Type | Description |
| :--- | :--- | :--- |
| `idle` | [Styled item](#styled-items) | Item to display when the reload indicator is off |
| `reload` | [Styled item](#styled-items) | Item to display when the reload indicator is on |

>[!TIP]
>Try using placeholders in mode- and reload-aware items to enhance feedback!

---

## Cache

The `Cache` section controls the page rendering cache, which speeds up navigation between recently viewed pages.

| Property | Type | Description |
| :--- | :--- | :--- |
| `enabled` | Boolean | Enables caching |
| `lru_size` | Integer | Maximum number of pages to store in the cache |
