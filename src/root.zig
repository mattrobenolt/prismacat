const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const testing = std.testing;
const assert = std.debug.assert;
const utf8ValidateSlice = std.unicode.utf8ValidateSlice;

const generated_themes = @import("generated_themes");
pub const Color = generated_themes.Color;
pub const Theme = generated_themes.Theme;
pub const themes = generated_themes.themes;

const ThemeMap = std.StaticStringMapWithEql(Theme, std.static_string_map.eqlAsciiIgnoreCase);

const theme_map: ThemeMap = .initComptime(blk: {
    var kvs: [themes.len]struct { []const u8, Theme } = undefined;
    for (themes, 0..) |theme, idx| kvs[idx] = .{ theme.name, theme };
    break :blk kvs;
});

pub const default_theme = theme_map.get("12-bit Rainbow").?;

pub const Options = struct {
    spread: u16 = 50,
    angle: Angle = .diagonal,
};

pub const Angle = enum {
    horizontal,
    diagonal,
};

pub fn findTheme(name: []const u8) ?Theme {
    return theme_map.get(name);
}

pub fn writeThemeNames(writer: *Io.Writer) Io.Writer.Error!void {
    for (themes) |theme| try writer.print("  {s}\n", .{theme.name});
}

pub fn writeDemo(writer: *Io.Writer, options: Options) Io.Writer.Error!void {
    for (themes) |theme| {
        try writer.print("\n{s}\n", .{theme.name});
        try colorizeWithOptions(demo_text, writer, theme, options);
        try writer.writeAll("\n");
    }
}

const demo_text =
    \\  ┌──────────────────────────────────────────┐
    \\  │ prismacat: themed truecolor terminal cat │
    \\  └──────────────────────────────────────────┘
    \\        /\_/\\
    \\       ( o.o )  rainbows, but make them weird
    \\        > ^ <
    \\
;

pub fn colorize(input: []const u8, writer: *Io.Writer, theme: Theme) Io.Writer.Error!void {
    try colorizeWithOptions(input, writer, theme, .{});
}

pub fn colorizeWithOptions(input: []const u8, writer: *Io.Writer, theme: Theme, options: Options) Io.Writer.Error!void {
    var colorizer: Colorizer = .init(writer, theme, options);
    try colorizer.write(input);
    try colorizer.finish();
}

pub const Colorizer = struct {
    writer: *Io.Writer,
    theme: Theme,
    options: Options,
    row: usize = 0,
    column: usize = 0,
    pending: [4]u8 = undefined,
    pending_len: u3 = 0,

    pub fn init(writer: *Io.Writer, theme: Theme, options: Options) Colorizer {
        assert(theme.stops.len > 0);
        assert(options.spread > 0);
        return .{ .writer = writer, .theme = theme, .options = options };
    }

    pub fn write(self: *Colorizer, input: []const u8) Io.Writer.Error!void {
        var bytes = input;

        if (self.pending_len > 0) {
            var combined: [4]u8 = undefined;
            @memcpy(combined[0..self.pending_len], self.pending[0..self.pending_len]);

            const needed = utf8ExpectedLen(combined[0]) orelse 1;
            const take = @min(needed - self.pending_len, bytes.len);
            @memcpy(combined[self.pending_len..][0..take], bytes[0..take]);
            self.pending_len += @intCast(take);
            bytes = bytes[take..];

            if (self.pending_len < needed) return;

            const slice = combined[0..needed];
            if (utf8ValidateSlice(slice)) {
                self.pending_len = 0;
                try self.writeCodepoint(slice);
            } else {
                self.pending_len = 0;
                try self.writeCodepoint(slice[0..1]);
                if (needed > 1) try self.write(slice[1..]);
            }
        }

        var i: usize = 0;
        while (i < bytes.len) {
            const expected = utf8ExpectedLen(bytes[i]) orelse 1;
            if (i + expected > bytes.len) {
                const remaining = bytes[i..];
                @memcpy(self.pending[0..remaining.len], remaining);
                self.pending_len = @intCast(remaining.len);
                return;
            }

            const slice = bytes[i..][0..expected];
            i += expected;
            if (expected > 1 and !utf8ValidateSlice(slice)) {
                try self.writeCodepoint(slice[0..1]);
                i -= expected - 1;
                continue;
            }
            try self.writeCodepoint(slice);
        }
    }

    pub fn finish(self: *Colorizer) Io.Writer.Error!void {
        for (self.pending[0..self.pending_len]) |byte| {
            try self.writeCodepoint((&byte)[0..1]);
        }
        self.pending_len = 0;
        try self.writer.writeAll("\x1b[0m");
    }

    fn writeCodepoint(self: *Colorizer, slice: []const u8) Io.Writer.Error!void {
        if (mem.eql(u8, slice, "\n")) {
            self.row += 1;
            self.column = 0;
            try self.writer.writeAll("\x1b[0m");
            try self.writer.writeAll(slice);
            return;
        }
        if (mem.eql(u8, slice, "\r")) {
            self.column = 0;
            try self.writer.writeAll("\x1b[0m");
            try self.writer.writeAll(slice);
            return;
        }

        const position = switch (self.options.angle) {
            .horizontal => self.column,
            .diagonal => self.column + self.row,
        };
        const color = sample(self.theme, position, self.options.spread);
        self.column += 1;
        try self.writer.print("\x1b[38;2;{d};{d};{d}m{s}", .{ color.r, color.g, color.b, slice });
    }
};

fn utf8ExpectedLen(first: u8) ?usize {
    return std.unicode.utf8ByteSequenceLength(first) catch null;
}

fn sample(theme: Theme, index: usize, cycle: usize) Color {
    if (theme.stops.len == 1) return theme.stops[0];

    const scale = 256;
    const phase = (index * scale * theme.stops.len / cycle) % (scale * theme.stops.len);
    const start_index = phase / scale;
    const end_index = (start_index + 1) % theme.stops.len;
    const amount = phase % scale;

    return mix(theme.stops[start_index], theme.stops[end_index], amount);
}

fn mix(a: Color, b: Color, amount: usize) Color {
    const inverse = 256 - amount;
    return .{
        .r = channel(a.r, b.r, inverse, amount),
        .g = channel(a.g, b.g, inverse, amount),
        .b = channel(a.b, b.b, inverse, amount),
    };
}

fn channel(a: u8, b: u8, inverse: usize, amount: usize) u8 {
    const value = (@as(usize, a) * inverse + @as(usize, b) * amount) / 256;
    return @intCast(value);
}

test "theme lookup" {
    try testing.expect(findTheme("Dracula") != null);
    try testing.expect(findTheme("dracula") != null);
    try testing.expect(findTheme("bog witch") == null);
}

test "utf8 slices stay intact" {
    try testing.expectEqual(@as(?usize, 1), utf8ExpectedLen('a'));
    try testing.expectEqual(@as(?usize, 4), utf8ExpectedLen("🌈"[0]));
}

test "colorize resets output" {
    var buffer: [256]u8 = undefined;
    var writer: Io.Writer = .fixed(&buffer);

    try colorizeWithOptions("ab\n", &writer, findTheme("Dracula").?, .{ .spread = 8 });

    const output = writer.buffered();
    try testing.expect(mem.find(u8, output, "\x1b[38;2;") != null);
    try testing.expect(mem.endsWith(u8, output, "\x1b[0m"));
}
