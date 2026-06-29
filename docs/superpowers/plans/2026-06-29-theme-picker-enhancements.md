# Theme Picker: Favorites + Creator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the in-terminal theme picker with a favorites/likes system, sort/filter tabs, and a creator mode with native platform color picker.

**Architecture:** A `ThemeMeta` module handles persistent JSON read/write for favorites and creations. `Surface.zig`'s `ThemePicker` gains an enum-based mode (browse/creator) and new key handling. A new `open_color_picker` action/message pair enables bidirectional native color picker communication between Zig and each app runtime.

**Tech Stack:** Zig, Swift (macOS), GTK (Linux)

## Global Constraints

- Use `std.json` for persistence — no new dependencies
- New actions go at the end of `ghostty_action_tag_e` in `include/ghostty.h`
- New messages go at the end of `apprt/surface.zig` `Message` union
- Theme file format matches existing Ghostty config syntax
- Color type is `[3]u8` (RGB)
- Palette edits cover ANSI 0-15 only

---

### Task 1: Theme Metadata Persistence

**Files:**
- Create: `src/config/ThemeMeta.zig`
- Test: add tests inline

**Interfaces:**
- Consumes: `std.json`, `std.fs`
- Produces: `ThemeMeta` struct with `load`, `save`, `toggleFavorite`, `addCreation`, `isFavorite`, `isCreation` methods

- [ ] **Step 1: Write the failing tests**

Create `src/config/ThemeMeta.zig` with test stubs:

```zig
const std = @import("std");
const testing = std.testing;

pub const ThemeMeta = struct {
    favorites: std.StringHashMap(void),
    creations: std.StringHashMap(void),
    alloc: Allocator,
    path: []const u8,

    pub const Allocator = std.mem.Allocator;

    pub fn init(alloc: Allocator, path: []const u8) ThemeMeta {
        return .{
            .favorites = std.StringHashMap(void).init(alloc),
            .creations = std.StringHashMap(void).init(alloc),
            .alloc = alloc,
            .path = path,
        };
    }

    pub fn deinit(self: *ThemeMeta) void {
        self.favorites.deinit();
        self.creations.deinit();
    }

    pub fn load(self: *ThemeMeta) !void {
        // Read JSON from path, populate favorites/creations
    }

    pub fn save(self: *ThemeMeta) !void {
        // Write JSON to path
    }

    pub fn toggleFavorite(self: *ThemeMeta, name: []const u8) !bool {
        // Toggle and persist. Returns new state (true = favorited)
    }

    pub fn addCreation(self: *ThemeMeta, name: []const u8) !void {
        // Mark as created and persist
    }

    pub fn isFavorite(self: *ThemeMeta, name: []const u8) bool {
        return self.favorites.contains(name);
    }

    pub fn isCreation(self: *ThemeMeta, name: []const u8) bool {
        return self.creations.contains(name);
    }
};
```

Then write tests:

```zig
test "ThemeMeta: roundtrip empty" {
    const alloc = testing.allocator;
    const dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const path = try std.fs.path.join(alloc, &.{ dir.path, "theme-meta.json" });
    defer alloc.free(path);

    var meta = ThemeMeta.init(alloc, path);
    defer meta.deinit();

    try meta.save();
    try meta.load();
    try testing.expect(!meta.isFavorite("test-theme"));
}

test "ThemeMeta: toggle favorite" {
    const alloc = testing.allocator;
    const dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const path = try std.fs.path.join(alloc, &.{ dir.path, "theme-meta.json" });
    defer alloc.free(path);

    var meta = ThemeMeta.init(alloc, path);
    defer meta.deinit();

    const added = try meta.toggleFavorite("catppuccin-mocha");
    try testing.expect(added);
    try testing.expect(meta.isFavorite("catppuccin-mocha"));

    const removed = try meta.toggleFavorite("catppuccin-mocha");
    try testing.expect(!removed);
    try testing.expect(!meta.isFavorite("catppuccin-mocha"));
}

test "ThemeMeta: add creation" {
    const alloc = testing.allocator;
    const dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const path = try std.fs.path.join(alloc, &.{ dir.path, "theme-meta.json" });
    defer alloc.free(path);

    var meta = ThemeMeta.init(alloc, path);
    defer meta.deinit();

    try meta.addCreation("my-theme");
    try testing.expect(meta.isCreation("my-theme"));
}

test "ThemeMeta: load persists across instances" {
    const alloc = testing.allocator;
    const dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const path = try std.fs.path.join(alloc, &.{ dir.path, "theme-meta.json" });
    defer alloc.free(path);

    {
        var meta = ThemeMeta.init(alloc, path);
        defer meta.deinit();
        _ = try meta.toggleFavorite("tokyo-night");
    }

    {
        var meta = ThemeMeta.init(alloc, path);
        defer meta.deinit();
        try meta.load();
        try testing.expect(meta.isFavorite("tokyo-night"));
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test -Dtest-filter="ThemeMeta"`
Expected: FAIL with 4 failures (no functions defined)

- [ ] **Step 3: Write minimal implementation**

```zig
const std = @import("std");
const log = std.log.scoped(.theme_meta);

pub const ThemeMeta = struct {
    favorites: std.StringHashMap(void),
    creations: std.StringHashMap(void),
    alloc: Allocator,
    path: []const u8,

    pub const Allocator = std.mem.Mem.Allocator;

    pub fn init(alloc: Allocator, path: []const u8) ThemeMeta {
        return .{
            .favorites = std.StringHashMap(void).init(alloc),
            .creations = std.StringHashMap(void).init(alloc),
            .alloc = alloc,
            .path = path,
        };
    }

    pub fn deinit(self: *ThemeMeta) void {
        self.favorites.deinit();
        self.creations.deinit();
    }

    pub fn load(self: *ThemeMeta) !void {
        const file = std.fs.openFileAbsolute(self.path, .{ .mode = .read_only }) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close();

        const data = try file.readToEndAlloc(self.alloc, std.math.maxInt(usize));
        defer self.alloc.free(data);

        var scanner = std.json.Scanner.initComplete(self.alloc, data);
        defer scanner.deinit();
        var map = std.json.ObjectMap.init(self.alloc);
        try scanner.scan(&map);

        if (map.get("favorites")) |arr| {
            if (arr == .array) {
                for (arr.array.items) |item| {
                    if (item == .string) {
                        self.favorites.put(item.string, {}) catch {};
                    }
                }
            }
        }
        if (map.get("creations")) |arr| {
            if (arr == .array) {
                for (arr.array.items) |item| {
                    if (item == .string) {
                        self.creations.put(item.string, {}) catch {};
                    }
                }
            }
        }
    }

    pub fn save(self: *ThemeMeta) !void {
        // Ensure parent dir exists
        if (std.fs.path.dirname(self.path)) |dir| {
            try std.fs.cwd().makePath(dir);
        }

        var buf = std.ArrayList(u8).init(self.alloc);
        defer buf.deinit();

        var w = buf.writer();
        try w.writeAll("{\n  \"favorites\": [\n");
        var first = true;
        var fav_it = self.favorites.iterator();
        while (fav_it.next()) |entry| {
            if (!first) try w.writeAll(",\n");
            first = false;
            try w.print("    \"{s}\"", .{entry.key_ptr.*});
        }
        try w.writeAll("\n  ],\n  \"creations\": [\n");
        first = true;
        var cr_it = self.creations.iterator();
        while (cr_it.next()) |entry| {
            if (!first) try w.writeAll(",\n");
            first = false;
            try w.print("    \"{s}\"", .{entry.key_ptr.*});
        }
        try w.writeAll("\n  ]\n}\n");

        // Write to temp then rename (atomic)
        const tmp_path = try std.fs.path.join(self.alloc, &.{ self.path, ".tmp" });
        defer self.alloc.free(tmp_path);
        var tmp = try std.fs.createFileAbsolute(tmp_path, .{ .truncate = true });
        defer tmp.close();
        try tmp.writeAll(buf.items);
        try std.fs.renameAbsolute(tmp_path, self.path);
    }

    pub fn toggleFavorite(self: *ThemeMeta, name: []const u8) !bool {
        if (self.favorites.contains(name)) {
            self.favorites.remove(name);
            try self.save();
            return false;
        } else {
            try self.favorites.put(try self.alloc.dupe(u8, name), {});
            try self.save();
            return true;
        }
    }

    pub fn addCreation(self: *ThemeMeta, name: []const u8) !void {
        try self.creations.put(try self.alloc.dupe(u8, name), {});
        try self.save();
    }

    pub fn isFavorite(self: *ThemeMeta, name: []const u8) bool {
        return self.favorites.contains(name);
    }

    pub fn isCreation(self: *ThemeMeta, name: []const u8) bool {
        return self.creations.contains(name);
    }
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `zig build test -Dtest-filter="ThemeMeta"`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add src/config/ThemeMeta.zig
git commit -m "theme-picker: add ThemeMeta persistence for favorites and creations"
```

---

### Task 2: Browse mode favorites + sort tabs

**Files:**
- Modify: `src/Surface.zig` (ThemePicker struct, key handler, render)

**Interfaces:**
- Consumes: `ThemeMeta` from Task 1
- Produces: Extended `ThemePicker` with mode enum, sort_tab, favorites map, creator state

- [ ] **Step 1: Add ThemeMeta import and state fields to Surface.zig**

At top of `Surface.zig`, add import:
```zig
const ThemeMeta = @import("config/ThemeMeta.zig").ThemeMeta;
```

In the `ThemePicker` struct, add fields:
```zig
mode: enum { browse, creator } = .browse,
sort_tab: enum { all, favorites, created } = .all,
meta: ?ThemeMeta = null,
creator: ?CreatorState = null,
```

In `line 224-284` of `Surface.zig`, update the `ThemePicker` struct to include these new fields and a `Mode` type. Add the `CreatorState` struct after `ThemeEntry`:

```zig
const CreatorState = struct {
    const Color = [3]u8;

    name: std.ArrayList(u8),
    background: Color,
    foreground: Color,
    palette: [16]Color,
    cursor_color: Color,
    cursor_text: Color,
    selection_bg: Color,
    selection_fg: Color,
    opacity: f64,
    focused_field: usize,
    pending_color_picker: ?usize,
};
```

- [ ] **Step 2: Initialize ThemeMeta in themePickerOpen**

In `themePickerOpen`, after `base_config` is created, resolve the theme-meta path and load it:

```zig
// Load theme metadata (favorites, creations)
const config_dir_path = configpkg.preferredDefaultFilePath(self.alloc) catch |err| {
    log.warn("failed to resolve config dir for theme-meta: {}", .{err});
    return false;
};
defer self.alloc.free(config_dir_path);
const config_dir = std.fs.path.dirname(config_dir_path) orelse {
    log.warn("no config dir for theme-meta", .{});
    return false;
};
const meta_path = try std.fs.path.join(self.alloc, &.{ config_dir, "theme-meta.json" });
var meta = ThemeMeta.init(self.alloc, meta_path);
meta.load() catch |err| {
    log.warn("failed to load theme-meta: {}", .{err});
};
```

Add `meta` to the picker init (line 397-411), but ThemeMeta needs to be moved into the picker (it has its own allocator):

```zig
self.theme_picker = .{
    ...
    .meta = meta,
    ...
};
```

- [ ] **Step 3: Add sort tab filtering to themePickerFilter**

Modify `themePickerFilter` to apply three-way filtering:

```zig
fn themePickerFilter(self: *Surface) !void {
    const picker = &(self.theme_picker orelse return);

    // Clear existing filter
    picker.filtered.clearRetainingCapacity();

    const query = std.ascii.lowerString(picker.query.items);

    for (picker.themes, 0..) |theme, i| {
        // Apply sort tab filter
        switch (picker.sort_tab) {
            .favorites => {
                if (picker.meta) |meta| {
                    if (!meta.isFavorite(theme.name)) continue;
                } else continue;
            },
            .created => {
                if (picker.meta) |meta| {
                    if (!meta.isCreation(theme.name)) continue;
                } else continue;
            },
            .all => {},
        }

        // Apply search query filter
        if (query.len > 0) {
            const name_lower = std.ascii.lowerString(theme.name);
            if (std.mem.indexOf(u8, name_lower, query) == null) continue;
        }

        try picker.filtered.append(i);
    }

    // Reset selection if out of bounds
    if (picker.selected >= picker.filtered.items.len and picker.filtered.items.len > 0) {
        picker.selected = 0;
        picker.scroll_offset = 0;
    }
}
```

- [ ] **Step 4: Add favorite toggle key in themePickerHandleKey**

In the key handler (`themePickerHandleKey`), add a case for `l`:

```zig
.key_l => {
    if (picker.filtered.items.len > 0 and picker.meta) |*meta| {
        const idx = picker.filtered.items[picker.selected];
        _ = meta.toggleFavorite(picker.themes[idx].name) catch |err| {
            log.warn("failed to toggle favorite: {}", .{err});
        };
    }
},
```

- [ ] **Step 5: Add sort tab switching keys**

In the key handler, use `h`/`l` to cycle sort tabs in browse mode:

```zig
.key_h => {
    if (picker.mode != .browse) return;
    const tag = @intFromEnum(picker.sort_tab);
    picker.sort_tab = if (tag > 0)
        @enumFromInt(tag - 1)
    else
        @enumFromInt(@typeInfo(@TypeOf(picker.sort_tab)).@"enum".fields.len - 1);
    try self.themePickerFilter();
    picker.selected = 0;
    picker.scroll_offset = 0;
},
.key_l => {
    // Favorite toggle (existing)
    // ... existing favorite toggle code ...
    return; // important: don't fall through to sort tab code
},

// Add after the favorite l case for the sort tab cycling via right arrow:
.key_arrow_right => {
    if (picker.mode == .browse) {
        // Only if not on opacity field (opacity adjustment is left/right independent)
        const tag = @intFromEnum(picker.sort_tab);
        picker.sort_tab = if (tag < @typeInfo(@TypeOf(picker.sort_tab)).@"enum".fields.len - 1)
            @enumFromInt(tag + 1)
        else
            @enumFromInt(0);
        try self.themePickerFilter();
        picker.selected = 0;
        picker.scroll_offset = 0;
        return;
    }
    // else: fall through to existing opacity slider behavior
},
.key_arrow_left => {
    if (picker.mode == .browse) {
        const tag = @intFromEnum(picker.sort_tab);
        picker.sort_tab = if (tag > 0)
            @enumFromInt(tag - 1)
        else
            @enumFromInt(@typeInfo(@TypeOf(picker.sort_tab)).@"enum".fields.len - 1);
        try self.themePickerFilter();
        picker.selected = 0;
        picker.scroll_offset = 0;
        return;
    }
    // else: fall through to existing opacity slider behavior
},
```

Use `h`/`l` for sort tab cycling in browse mode, keeping left/right for opacity:

```zig
.key_h => {
    if (picker.mode != .browse) return;
    const tag = @intFromEnum(picker.sort_tab);
    picker.sort_tab = if (tag > 0)
        @enumFromInt(tag - 1)
    else
        @enumFromInt(@typeInfo(@TypeOf(picker.sort_tab)).@"enum".fields.len - 1);
    try self.themePickerFilter();
    picker.selected = 0;
    picker.scroll_offset = 0;
},
```

- [ ] **Step 6: Update render to show sort tabs and favorite indicators**

In `themePickerRender`, add a header row showing `[All] [Favorites] [Created]` with the active one highlighted, and per-theme favorite markers:

The current render function (line 467-684) draws the picker rows. Modify the header section to include sort tabs. The row right after the search bar can show:

```zig
// Sort tabs
const tab_names = [_][]const u8{ "All", "Fav", "Own" };
for (tab_names, 0..) |name, i| {
    const active = @intFromEnum(picker.sort_tab) == i;
    // Write tab name with brackets, active one is highlighted
    // e.g. [All] [Fav] [Own]
}
```

For theme entries, prefix with `★` if favorited, `+` if created, or nothing:

```zig
// In the theme row rendering:
if (picker.meta) |meta| {
    if (meta.isFavorite(picker.themes[theme_idx].name)) {
        // draw ★
    } else if (meta.isCreation(picker.themes[theme_idx].name)) {
        // draw +
    }
}
// draw theme name
```

- [ ] **Step 7: Build and run to verify**

Run: `zig build -Demit-macos-app=false`
Expected: Build succeeds with no errors

- [ ] **Step 8: Commit**

```bash
git add src/Surface.zig
git commit -m "theme-picker: add favorites toggle and sort tabs to browse mode"
```

---

### Task 3: Creator mode form + save + hex color input

**Files:**
- Modify: `src/Surface.zig`

**Interfaces:**
- Consumes: config serialization helpers from Task 1. Color picker action from Task 4 (consumed via future integration — use hex fallback first)
- Produces: Full creator mode with form rendering, field editing, save flow

- [ ] **Step 1: Add mode switching via Tab**

In `themePickerHandleKey`, handle Tab to toggle between browse/creator:

```zig
.key_tab => {
    picker.mode = if (picker.mode == .browse) .creator else .browse;
    if (picker.mode == .creator) {
        // Initialize creator state from selected theme if not yet initialized
        if (picker.creator == null) {
            // Clone current preview config into creator state
            try self.themePickerInitCreator();
        }
    }
    try self.themePickerRender();
},
```

`themePickerInitCreator` populates `CreatorState` from the currently selected theme's config:

```zig
fn themePickerInitCreator(self: *Surface) !void {
    const picker = &(self.theme_picker orelse return);
    const picker_state = picker;

    // Get the currently selected theme
    if (picker_state.filtered.items.len == 0) return;
    const idx = picker_state.filtered.items[picker_state.selected];
    const theme = picker_state.themes[idx];

    // Load the theme to get its colors
    var config = picker_state.base_config.?.clone(self.alloc) catch return;
    defer config.deinit();
    config.loadFile(self.alloc, theme.path) catch return;
    config.finalize() catch return;

    // Helper to read a color from config
    const Color = CreatorState.Color;
    const bg_color: Color = .{ config.background.r, config.background.g, config.background.b };
    const fg_color: Color = .{ config.foreground.r, config.foreground.g, config.foreground.b };
    const cur_color: Color = .{ config.cursor_color.r, config.cursor_color.g, config.cursor_color.b };
    const cur_text: Color = .{ config.cursor_text.r, config.cursor_text.g, config.cursor_text.b };
    const sel_bg: Color = .{ config.selection_background.r, config.selection_background.g, config.selection_background.b };
    const sel_fg: Color = .{ config.selection_foreground.r, config.selection_foreground.g, config.selection_foreground.b };
    var palette: [16]Color = undefined;
    inline for (0..16) |i| {
        const p = config.palette(i);
        palette[i] = .{ p.r, p.g, p.b };
    }

    picker_state.creator = CreatorState{
        .name = std.ArrayList(u8).init(self.alloc),
        .background = bg_color,
        // ... etc
        .opacity = config.@"background-opacity",
        .focused_field = 0,
        .pending_color_picker = null,
    };
    // Set name from theme name
    try picker_state.creator.?.name.appendSlice(theme.name);
}
```

- [ ] **Step 2: Replace old favorite `l` key with dedicated favorite toggle**

Since Tab now cycles sort tabs in browse mode, and `l` does favorite toggle, update the key handler to use `l` for favorite in browse mode and `l` does nothing (or reserved for favorite) in creator mode.

- [ ] **Step 3: Render creator form**

In `themePickerRender`, when `mode == .creator`, render a form instead of the theme list:

```zig
if (picker.mode == .creator) {
    try self.themePickerRenderCreator();
    return;
}
```

`themePickerRenderCreator` draws a form like:

```
┌─ Theme Creator ─────────────────────┐
│ Name: [my-theme              ]      │
│ Background: #1e1e2e                 │
│ Foreground: #cdd6f4                 │
│ Palette 0:  #45475a                 │
│ Palette 1:  #f38ba8                 │
│ ...                                 │
│ Cursor:     #f5e0dc                 │
│ Cursor Text: #1e1e2e                │
│ Selection BG: #585b70               │
│ Selection FG: #cdd6f4               │
│ Opacity: [████████░░░░] 50%         │
│                                      │
│ [Ctrl+S to save, Esc to go back]   │
└──────────────────────────────────────┘
```

The focused field is highlighted. Color values show as hex `#RRGGBB`.

- [ ] **Step 4: Creator mode key handling**

In `themePickerHandleKey`, when `mode == .creator`, handle:

```zig
if (picker.mode == .creator) {
    return self.themePickerHandleKeyCreator(event);
}
```

```zig
fn themePickerHandleKeyCreator(self: *Surface, event: input.KeyEvent) !void {
    const picker = &(self.theme_picker orelse return);
    const creator = &(picker.creator orelse return);

    const field_count = 23; // 0=name,1=bg,2=fg,3-18=palette,19=cursor,20=cursor_text,21=sel_bg,22=sel_fg,23=opacity

    switch (event.key) {
        .escape => {
            // Go back to browse mode without saving
            picker.mode = .browse;
            try self.themePickerRender();
            return;
        },
        .arrow_up => {
            if (creator.focused_field > 0) {
                creator.focused_field -= 1;
            }
            try self.themePickerRender();
            return;
        },
        .arrow_down => {
            if (creator.focused_field < field_count - 1) {
                creator.focused_field += 1;
            }
            try self.themePickerRender();
            return;
        },
        .arrow_left => {
            if (creator.focused_field == 23) { // opacity field
                creator.opacity = @max(0.15, creator.opacity - 0.05);
                try self.themePickerPreviewFromCreator();
                try self.themePickerRender();
            }
        },
        .arrow_right => {
            if (creator.focused_field == 23) { // opacity field
                creator.opacity = @min(1.0, creator.opacity + 0.05);
                try self.themePickerPreviewFromCreator();
                try self.themePickerRender();
            }
        },
        .key_s => {
            // Ctrl+s to save (check for ctrl modifier)
            if (event.mods.ctrl) {
                try self.themePickerSaveCreator();
            }
        },
        .enter => {
            // Open color picker for the focused field
            // For now, use hex input fallback
            if (creator.focused_field >= 2 and creator.focused_field < field_count - 1) {
                // Open native color picker (Task 4)
                // Fallback: allow hex input
            }
        },
        else => {
            // If focused on name field, append typed character
            if (creator.focused_field == 0) {
                if (event.utf8.len > 0) {
                    try creator.name.appendSlice(event.utf8);
                }
            }
        },
    }
}
```

- [ ] **Step 5: Hex input fallback for color fields**

When Enter is pressed on a color field, prompt the user for hex input. This is a simplified approach that works before the native color picker is integrated.

In the creator key handler, when Enter is pressed on a color field, set a flag and wait for hex input mode:

```zig
.enter => {
    if (creator.focused_field >= 2 and creator.focused_field < field_count - 1) {
        // Transition to hex input mode
        creator.hex_input = std.ArrayList(u8).init(self.alloc);
    }
},
```

Then in the else branch, if hex_input is active, handle hex characters.

(Note: This is simpler to implement by focusing on native color picker from the start and making hex editing a fallback for headless/embedded targets.)

- [ ] **Step 6: Live preview from creator state**

```zig
fn themePickerPreviewFromCreator(self: *Surface) !void {
    const picker = &(self.theme_picker orelse return);
    const creator = &(picker.creator orelse return);
    const base = picker.base_config orelse return;

    var config = try base.clone(self.alloc);
    defer config.deinit();

    // Apply creator colors
    config.background = .{ .r = creator.background[0], .g = creator.background[1], .b = creator.background[2] };
    config.foreground = .{ .r = creator.foreground[0], .g = creator.foreground[1], .b = creator.foreground[2] };
    config.cursor_color = .{ .r = creator.cursor_color[0], .g = creator.cursor_color[1], .b = creator.cursor_color[2] };
    config.cursor_text = .{ .r = creator.cursor_text[0], .g = creator.cursor_text[1], .b = creator.cursor_text[2] };
    config.selection_background = .{ .r = creator.selection_bg[0], .g = creator.selection_bg[1], .b = creator.selection_bg[2] };
    config.selection_foreground = .{ .r = creator.selection_fg[0], .g = creator.selection_fg[1], .b = creator.selection_fg[2] };

    // Apply palette
    inline for (0..16) |i| {
        const color_key = std.fmt.comptimePrint("palette_{d}", .{i});
        @field(config, color_key) = .{
            .r = creator.palette[i][0],
            .g = creator.palette[i][1],
            .b = creator.palette[i][2],
        };
    }

    config.finalize() catch return;
    config.@"background-opacity" = creator.opacity;

    self.app.updateConfig(self.rt_app, &config) catch |err| {
        log.warn("failed to preview creator config: {}", .{err});
    };
}
```

- [ ] **Step 7: Save creator theme to file**

```zig
fn themePickerSaveCreator(self: *Surface) !void {
    const picker = &(self.theme_picker orelse return);
    const creator = &(picker.creator orelse return);

    // Get theme name
    const name = creator.name.items;
    if (name.len == 0) return; // need a name

    // Build path
    const config_dir_path = try configpkg.preferredDefaultFilePath(self.alloc);
    defer self.alloc.free(config_dir_path);
    const config_dir = std.fs.path.dirname(config_dir_path) orelse return;
    const themes_dir = try std.fs.path.join(self.alloc, &.{ config_dir, "themes" });
    defer self.alloc.free(themes_dir);
    try std.fs.cwd().makePath(themes_dir);

    // Write .ghostty theme file
    const filename = try std.fmt.allocPrint(self.alloc, "{s}.ghostty", .{name});
    defer self.alloc.free(filename);
    const filepath = try std.fs.path.join(self.alloc, &.{ themes_dir, filename });
    defer self.alloc.free(filepath);

    var file = try std.fs.createFileAbsolute(filepath, .{ .truncate = true });
    defer file.close();
    var buf: [1024]u8 = undefined;
    var w = file.writer(&buf);

    try w.print("background = #{x:0>2}{x:0>2}{x:0>2}\n", .{ creator.background[0], creator.background[1], creator.background[2] });
    try w.print("foreground = #{x:0>2}{x:0>2}{x:0>2}\n", .{ creator.foreground[0], creator.foreground[1], creator.foreground[2] });
    try w.print("cursor-color = #{x:0>2}{x:0>2}{x:0>2}\n", .{ creator.cursor_color[0], creator.cursor_color[1], creator.cursor_color[2] });
    try w.print("cursor-text = #{x:0>2}{x:0>2}{x:0>2}\n", .{ creator.cursor_text[0], creator.cursor_text[1], creator.cursor_text[2] });
    try w.print("selection-background = #{x:0>2}{x:0>2}{x:0>2}\n", .{ creator.selection_bg[0], creator.selection_bg[1], creator.selection_bg[2] });
    try w.print("selection-foreground = #{x:0>2}{x:0>2}{x:0>2}\n", .{ creator.selection_fg[0], creator.selection_fg[1], creator.selection_fg[2] });
    inline for (0..16) |i| {
        try w.print("palette = {d}=#{x:0>2}{x:0>2}{x:0>2}\n", .{ i, creator.palette[i][0], creator.palette[i][1], creator.palette[i][2] });
    }
    try w.print("background-opacity = {d:.2}\n", .{creator.opacity});

    // Mark as creation
    if (picker.meta) |*meta| {
        meta.addCreation(name) catch |err| {
            log.warn("failed to mark creation: {}", .{err});
        };
    }

    // Re-add to themes list if not already present
    // ...
}
```

- [ ] **Step 8: Build and verify**

Run: `zig build -Demit-macos-app=false`
Expected: Build succeeds

- [ ] **Step 9: Commit**

```bash
git add src/Surface.zig
git commit -m "theme-picker: add creator mode with form editing, save, and live preview"
```

---

### Task 4: Native color picker cross-platform action

**Files:**
- Modify: `src/apprt/action.zig`
- Modify: `src/apprt/surface.zig`
- Modify: `include/ghostty.h`

**Interfaces:**
- Produces: `Action.open_color_picker` (Zig → apprt) and `Message.color_picker_result` (apprt → Zig)

- [ ] **Step 1: Add `open_color_picker` action**

In `src/apprt/action.zig`, add the action value struct and union entry. Add to the `Action` union after `color_change`:

```zig
/// Open the native platform color picker with an initial RGB color.
/// The app runtime should call back with `color_picker_result` message
/// on the surface.
open_color_picker: OpenColorPicker,
```

Add the struct:

```zig
pub const OpenColorPicker = extern struct {
    r: u8,
    g: u8,
    b: u8,
};
```

Add to the `Key` enum at the end (before the test):

```zig
open_color_picker,
```

- [ ] **Step 2: Update `ghostty.h`**

In `include/ghostty.h`, find the `ghostty_action_tag_e` enum and add `GHOSTTY_ACTION_OPEN_COLOR_PICKER` at the end, before `_MAX_VALUE`. Add the `ghostty_action_open_color_picker_s` struct and add it to the `ghostty_action_u` union.

Also add a new C API function so the app runtime can deliver the result back:
```c
GHOSTTY_API void ghostty_surface_color_picker_result(ghostty_surface_t, uint8_t r, uint8_t g, uint8_t b);
```

The Zig implementation dispatches to `surface.handleMessage(.{ .color_picker_result = .{ .r, .g, .b } })`.

- [ ] **Step 3: Add `color_picker_result` message**

In `src/apprt/surface.zig`, add to the `Message` union at the end:

```zig
/// Result from a native platform color picker.
color_picker_result: struct {
    r: u8,
    g: u8,
    b: u8,
},
```

- [ ] **Step 4: Implement surface-level message handling for color_picker_result**

In `Surface.zig`, find the `handleMessage` function and add handling for `color_picker_result`:

```zig
.color_picker_result => |result| {
    if (self.theme_picker) |*picker| {
        if (picker.creator) |*creator| {
            // Update the focused color field
            // ...
        }
    }
},
```

- [ ] **Step 5: Build and verify**

Run: `zig build -Demit-macos-app=false`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add src/apprt/action.zig src/apprt/surface.zig include/ghostty.h
git commit -m "theme-picker: add open_color_picker action and color_picker_result message"
```

---

### Task 5: macOS native color picker

**Files:**
- Modify: `macos/Sources/Ghostty/Ghostty.App.swift`
- Modify: `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` (or appropriate handler)

- [ ] **Step 1: Handle `open_color_picker` action in macOS**

In `Ghostty.App.swift`, in the action handler, add:

```swift
case GHOSTTY_ACTION_OPEN_COLOR_PICKER:
    Self.openColorPicker(app, target: target, v: action.action.open_color_picker)
```

Implement:

```swift
private static func openColorPicker(
    _ app: ghostty_app_t,
    target: ghostty_target_s,
    v: ghostty_action_open_color_picker_s
) {
    guard case .surface = target.tag else { return }
    guard let surface = target.target.surface,
          let surfaceView = self.surfaceView(from: surface) else { return }

    let initialColor = NSColor(
        red: CGFloat(v.r) / 255,
        green: CGFloat(v.g) / 255,
        blue: CGFloat(v.b) / 255,
        alpha: 1
    )

    let colorPanel = NSColorPanel.shared
    colorPanel.color = initialColor
    colorPanel.setAction(#selector(SurfaceView.colorPickerChanged(_:)))
    colorPanel.setTarget(surfaceView)
    colorPanel.makeKeyAndOrderFront(nil)
}
```

- [ ] **Step 2: Handle color picker result in SurfaceView**

In `SurfaceView_AppKit.swift`, add:

```swift
@objc func colorPickerChanged(_ sender: NSColorPanel) {
    let color = sender.color
    guard let srgbColor = color.usingColorSpace(.sRGB) else { return }

    let r = UInt8(srgbColor.redComponent * 255)
    let g = UInt8(srgbColor.greenComponent * 255)
    let b = UInt8(srgbColor.blueComponent * 255)

    // Send result back to surface via C API
    ghostty_surface_color_picker_result(self.surface, r, g, b)
}
```

- [ ] **Step 3: Build and verify**

Run: `macos/build.nu --configuration Debug --action build`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add macos/Sources/Ghostty/Ghostty.App.swift macos/Sources/Ghostty/Surface\ View/SurfaceView_AppKit.swift
git commit -m "theme-picker: add macOS native NSColorPanel integration"
```

---

### Task 6: GTK native color picker

**Files:**
- Modify: `src/apprt/gtk/` (application or window)

- [ ] **Step 1: Handle `open_color_picker` action in GTK**

In the GTK application action handler (likely `src/apprt/gtk/class/application.zig`), add a case for the new action that opens `GtkColorChooserDialog`.

- [ ] **Step 2: Handle color picker result in GTK**

When the dialog returns a color, call `surface.handleMessage(.{ .color_picker_result = .{ .r = ..., .g = ..., .b = ... } })`.

- [ ] **Step 3: Build and verify**

Run: `zig build -Demit-macos-app=false`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add src/apprt/gtk/
git commit -m "theme-picker: add GTK native color chooser integration"
```

---

### Task 7: Wire creator mode to native color picker

**Files:**
- Modify: `src/Surface.zig`

- [ ] **Step 1: Connect Enter in creator to `open_color_picker` action**

In `themePickerHandleKeyCreator`, when `Enter` is pressed on a color field, send the action:

```zig
.enter => {
    if (creator.focused_field >= 2 and creator.focused_field < field_count - 1) {
        const field = // get color from focused field index
        const color = // get current RGB value
        try self.rt_app.performAction(
            .{ .surface = self },
            .open_color_picker,
            .{ .open_color_picker = .{
                .r = color[0],
                .g = color[1],
                .b = color[2],
            } },
        );
        creator.pending_color_picker = creator.focused_field;
    }
},
```

- [ ] **Step 2: Handle `color_picker_result` in the creator**

In `handleMessage`, update the creator state field:

```zig
.color_picker_result => |result| {
    if (self.theme_picker) |*picker| {
        if (picker.creator) |*creator| {
            if (creator.pending_color_picker) |field_idx| {
                creator.pending_color_picker = null;
                // Update the appropriate color field based on field_idx
                // ...
                try self.themePickerPreviewFromCreator();
                try self.themePickerRender();
            }
        }
    }
},
```

- [ ] **Step 3: Build and verify**

Run: `zig build -Demit-macos-app=false`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add src/Surface.zig
git commit -m "theme-picker: wire creator mode to native color picker"
```
