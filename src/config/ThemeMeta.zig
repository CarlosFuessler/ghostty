const std = @import("std");
const testing = std.testing;
const log = std.log.scoped(.theme_meta);

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
        {
            var it = self.favorites.iterator();
            while (it.next()) |entry| {
                self.alloc.free(entry.key_ptr.*);
            }
        }
        {
            var it = self.creations.iterator();
            while (it.next()) |entry| {
                self.alloc.free(entry.key_ptr.*);
            }
        }
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

        self.clearKeys();

        var parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.alloc,
            data,
            .{},
        );
        defer parsed.deinit();
        const value = parsed.value;

        if (value == .object) {
            const map = value.object;
            if (map.get("favorites")) |arr| {
                if (arr == .array) {
                    for (arr.array.items) |item| {
                        if (item == .string) {
                            const name = try self.alloc.dupe(u8, item.string);
                            self.favorites.put(name, {}) catch {};
                        }
                    }
                }
            }
            if (map.get("creations")) |arr| {
                if (arr == .array) {
                    for (arr.array.items) |item| {
                        if (item == .string) {
                            const name = try self.alloc.dupe(u8, item.string);
                            self.creations.put(name, {}) catch {};
                        }
                    }
                }
            }
        }
    }

    fn clearKeys(self: *ThemeMeta) void {
        {
            var it = self.favorites.iterator();
            while (it.next()) |entry| {
                self.alloc.free(entry.key_ptr.*);
            }
        }
        self.favorites.clearRetainingCapacity();
        {
            var it = self.creations.iterator();
            while (it.next()) |entry| {
                self.alloc.free(entry.key_ptr.*);
            }
        }
        self.creations.clearRetainingCapacity();
    }

    pub fn save(self: *ThemeMeta) !void {
        if (std.fs.path.dirname(self.path)) |dir| {
            try std.fs.cwd().makePath(dir);
        }

        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.alloc);

        const w = buf.writer(self.alloc);
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

        const tmp_path = try std.fmt.allocPrint(self.alloc, "{s}.tmp", .{self.path});
        defer self.alloc.free(tmp_path);
        var tmp = try std.fs.createFileAbsolute(tmp_path, .{ .truncate = true });
        defer tmp.close();
        try tmp.writeAll(buf.items);
        try std.fs.renameAbsolute(tmp_path, self.path);
    }

    pub fn toggleFavorite(self: *ThemeMeta, name: []const u8) !bool {
        if (self.favorites.fetchRemove(name)) |kv| {
            self.alloc.free(kv.key);
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

    pub fn isFavorite(self: *const ThemeMeta, name: []const u8) bool {
        return self.favorites.contains(name);
    }

    pub fn isCreation(self: *const ThemeMeta, name: []const u8) bool {
        return self.creations.contains(name);
    }
};

test "ThemeMeta: roundtrip empty" {
    const alloc = testing.allocator;
    var dir = testing.tmpDir(.{});
    defer dir.cleanup();
    const dir_path = try dir.dir.realpathAlloc(alloc, ".");
    defer alloc.free(dir_path);
    const path = try std.fs.path.join(alloc, &.{ dir_path, "theme-meta.json" });
    defer alloc.free(path);

    var meta = ThemeMeta.init(alloc, path);
    defer meta.deinit();

    try meta.save();
    try meta.load();
    try testing.expect(!meta.isFavorite("test-theme"));
}

test "ThemeMeta: toggle favorite" {
    const alloc = testing.allocator;
    var dir = testing.tmpDir(.{});
    defer dir.cleanup();
    const dir_path = try dir.dir.realpathAlloc(alloc, ".");
    defer alloc.free(dir_path);
    const path = try std.fs.path.join(alloc, &.{ dir_path, "theme-meta.json" });
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
    var dir = testing.tmpDir(.{});
    defer dir.cleanup();
    const dir_path = try dir.dir.realpathAlloc(alloc, ".");
    defer alloc.free(dir_path);
    const path = try std.fs.path.join(alloc, &.{ dir_path, "theme-meta.json" });
    defer alloc.free(path);

    var meta = ThemeMeta.init(alloc, path);
    defer meta.deinit();

    try meta.addCreation("my-theme");
    try testing.expect(meta.isCreation("my-theme"));
}

test "ThemeMeta: load persists across instances" {
    const alloc = testing.allocator;
    var dir = testing.tmpDir(.{});
    defer dir.cleanup();
    const dir_path = try dir.dir.realpathAlloc(alloc, ".");
    defer alloc.free(dir_path);
    const path = try std.fs.path.join(alloc, &.{ dir_path, "theme-meta.json" });
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
