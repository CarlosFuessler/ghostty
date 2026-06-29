# Theme Picker: Favorites + Creator Mode

Date: 2026-06-29
Status: Draft

## Overview

Extend the existing in-terminal theme picker (`Surface.zig` `ThemePicker`) with:
1. **Favorites system** — star/like themes, persisted to disk
2. **Creator mode** — live color editing with native platform color picker
3. **Sort/filter tabs** — All / Favorites / Created views
4. **Save flow** — write edited themes as new `.ghostty` theme files

## Architecture

### Persistence Layer

A single JSON file at the platform config directory stores theme metadata:

```
~/.config/ghostty/theme-meta.json
  or
~/Library/Application Support/com.mitchellh.ghostty/theme-meta.json
```

Schema:
```json
{
  "favorites": ["catppuccin-mocha", "tokyo-night"],
  "creations": ["my-custom-theme"]
}
```

- File is read when the picker opens (`themePickerOpen`)
- Written atomically whenever a favorite is toggled or a theme is saved
- Theme identity is the filename (shown in the picker list)

### Browse Mode (Enhanced)

The existing picker UI is extended with:

**Favorites toggle** (`l` key):
- Press `l` on a selected theme to toggle favorite status
- Favorited themes shown with `★` prefix in the list

**Sort tabs** — header row shows:
```
[All] [Favorites] [Created]
```
- Left/right arrows navigate tabs
- Each tab filters the theme list:
  - All: all themes (default)
  - Favorites: only favorited themes
  - Created: only user-created themes
- Within each tab, themes are sorted alphabetically by name
- Tab state is tracked in the `ThemePicker` struct

### Creator Mode

Tab key toggles between Browse and Creator modes. The creator mode renders a form in place of the theme list. The form fields are:

| Field | Source |
|-------|--------|
| Theme name | Text input (free-form, becomes filename) |
| Background | Color |
| Foreground | Color |
| Palette 0-15 | Array of 16 ANSI colors |
| Cursor color | Color |
| Cursor text | Color |
| Selection BG | Color |
| Selection FG | Color |
| Opacity | Slider (0.15-1.0, same mechanism as browse mode) |

The form is navigated with up/down arrows. Pressing Enter on a color field triggers the native platform color picker.

### Native Platform Color Picker

A new bidirectional action system:

**Zig → App Runtime** (new `Action` variant):
```
Action.open_color_picker {
    field: ColorField,
    current_color: [3]u8 // RGB
}
```
The app runtime (macOS/GTK) opens the native color picker dialog.

**App Runtime → Zig** (new `Message` variant):
```
Message.color_picker_result {
    field: ColorField,
    color: [3]u8 // RGB
}
```
Zig receives the result, updates the creator form field, and triggers a live preview.

Implementation per platform:
- **macOS**: `NSColorPanel` as a window sheet
- **GTK**: `GtkColorChooserDialog`
- **Other** (headless/embedded): fall back to hex input

### Live Preview

Any edit in the creator mode triggers `themePickerPreview()` (the same mechanism used for Browse selection). This clones the base config, applies the edited values, and calls `App.updateConfig` for an instant preview.

### Save Flow

- Keybinding: `Ctrl+s`
- Validates theme name is non-empty
- Generates a theme file with only non-default values
- Writes to `~/.config/ghostty/themes/<name>.ghostty`
- Auto-marks as created in `theme-meta.json`
- Shows brief confirmation ("Saved!"), returns to creator mode

Theme file format (standard Ghostty config syntax):
```ini
background = #1e1e2e
foreground = #cdd6f4
palette = 0=#45475a
palette = 1=#f38ba8
...
background-opacity = 0.85
```

## Key Bindings Summary

| Key | Browse Mode | Creator Mode |
|-----|-------------|--------------|
| `Tab` | → Creator mode | → Browse mode |
| `Escape` | Close picker | → Browse mode |
| `l` | Toggle favorite | — |
| `Up/Down` | Navigate themes | Navigate form fields |
| `Left/Right` | Adjust opacity | Adjust opacity (on opacity field) |
| `Enter` | — | Open color picker for selected field |
| `Ctrl+s` | — | Save theme |
| Type | Search filter | Edit theme name |

## Data Structures

### `ThemePicker` struct additions

```zig
mode: enum { browse, creator },
favorites: std.StringHashMap(void),  // loaded from theme-meta.json
sort_tab: enum { all, favorites, created },

// Creator state
creator: ?CreatorState,
```

```zig
const Color = [3]u8; // RGB

const CreatorState = struct {
    name: []u8,
    background: Color,
    foreground: Color,
    palette: [16]Color, // 0-15 ANSI colors
    cursor_color: Color,
    cursor_text: Color,
    selection_bg: Color,
    selection_fg: Color,
    opacity: f64,
    focused_field: Field,
    pending_color_picker: ?Field,  // field awaiting picker result
};
```

## Files Modified

- `src/Surface.zig` — main ThemePicker changes, creator mode, key handling
- `src/apprt/action.zig` — new `open_color_picker` action
- `src/apprt/surface.zig` — new `color_picker_result` message
- `macos/Sources/Ghostty/Ghostty.App.swift` — handle `open_color_picker` action
- `macos/Sources/Features/Terminal/` — NSColorPanel integration
- `src/apprt/gtk/` — GtkColorChooser integration
- `src/config/Config.zig` — helper to serialize theme config to file

## Open Questions

- Should `theme-meta.json` use atomic writes (write to temp, rename)?
  - Yes, same pattern as `writeAutoThemeFile` in `list_themes.zig`
- Fallback for platforms without native color picker?
  - Hex input fallback in the terminal itself
