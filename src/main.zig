const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const process = std.process;
const Allocator = mem.Allocator;
const build_options = @import("build_options");

const prismacat = @import("prismacat");

const usage =
    \\Usage: prismacat [OPTIONS] [FILE...]
    \\
    \\Themeable truecolor cat. Reads FILEs, or stdin when no FILE is given.
    \\Use '-' as a FILE to read stdin explicitly.
    \\
    \\Options:
    \\  -t, --theme NAME             Theme to use (default: 12-bit Rainbow)
    \\  -s, --spread CHARS           Columns per full gradient cycle (default: 50)
    \\      --angle MODE             Gradient mode: diagonal or horizontal (default: diagonal)
    \\      --list-themes            List available themes
    \\      --demo                   Print sample output for every theme
    \\  -v, --version                Show version
    \\  -h, --help                   Show this help
    \\
    \\Examples:
    \\  fortune | cowsay | prismacat
    \\  prismacat --theme "Catppuccin Mocha" README.md
    \\  prismacat --demo --spread 36 | less -R
    \\
;

const Args = struct {
    theme: prismacat.Theme = prismacat.default_theme,
    options: prismacat.Options = .{},
    files: []const [:0]const u8 = &.{},
    list_themes: bool = false,
    demo: bool = false,
    help: bool = false,
    version: bool = false,
};

pub fn main(init: process.Init) u8 {
    return run(init) catch |err| switch (err) {
        error.WriteFailed => 0,
        else => {
            std.debug.print("prismacat: {t}\n", .{err});
            return 1;
        },
    };
}

fn run(init: process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;
    defer stderr.flush() catch {};

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;
    defer stdout.flush() catch {};

    var files: std.ArrayList([:0]const u8) = .empty;
    var arg_it = init.minimal.args.iterate();
    var args = parseArgs(arena, &arg_it, stderr, &files) catch return 1;

    if (args.help) {
        try stdout.writeAll(usage);
        return 0;
    }
    if (args.version) {
        try stdout.print("prismacat {s}\n", .{build_options.version});
        return 0;
    }
    if (args.list_themes) {
        try prismacat.writeThemeNames(stdout);
        return 0;
    }

    randomizeStart(io, &args.options);

    if (args.demo) {
        try prismacat.writeDemo(stdout, args.options);
        return 0;
    }

    if (args.files.len == 0) {
        try colorizeStdin(io, stdout, args);
        return 0;
    }

    var failed = false;
    for (args.files) |path| {
        if (mem.eql(u8, path, "-")) {
            colorizeStdin(io, stdout, args) catch |err| {
                failed = true;
                try reportInputError(stdout, stderr, "stdin", err);
            };
        } else {
            colorizeFile(io, stdout, path, args) catch |err| {
                failed = true;
                try reportInputError(stdout, stderr, path, err);
            };
        }
    }

    return if (failed) 1 else 0;
}

fn randomizeStart(io: Io, options: *prismacat.Options) void {
    var seed: u64 = undefined;
    io.random(mem.asBytes(&seed));
    options.offset = seed % options.spread;
}

fn reportInputError(stdout: *Io.Writer, stderr: *Io.Writer, path: []const u8, err: anyerror) !void {
    try stdout.writeAll("\x1b[0m");
    try stdout.flush();
    try stderr.print("prismacat: {s}: {t}\n", .{ path, err });
    try stderr.flush();
}

fn colorizeStdin(io: Io, stdout: *Io.Writer, args: Args) !void {
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_file_reader: Io.File.Reader = .init(.stdin(), io, &stdin_buffer);
    const stdin = &stdin_file_reader.interface;

    try colorizeReader(stdin, stdout, args);
}

fn colorizeFile(io: Io, stdout: *Io.Writer, path: []const u8, args: Args) !void {
    const file = try Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var file_buffer: [4096]u8 = undefined;
    var file_reader: Io.File.Reader = .init(file, io, &file_buffer);
    const reader = &file_reader.interface;

    try colorizeReader(reader, stdout, args);
}

fn colorizeReader(reader: *Io.Reader, stdout: *Io.Writer, args: Args) !void {
    var colorizer: prismacat.Colorizer = .init(stdout, args.theme, args.options);
    var buffer: [8192]u8 = undefined;

    while (true) {
        const n = try reader.readSliceShort(&buffer);
        if (n == 0) break;
        try colorizer.write(buffer[0..n]);
        if (n < buffer.len) break;
    }

    try colorizer.finish();
}

fn parseArgs(
    allocator: Allocator,
    argv: *process.Args.Iterator,
    stderr: *Io.Writer,
    files: *std.ArrayList([:0]const u8),
) !Args {
    var result: Args = .{};
    _ = argv.skip();

    while (argv.next()) |arg| {
        if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
            result.help = true;
        } else if (mem.eql(u8, arg, "--version") or mem.eql(u8, arg, "-v")) {
            result.version = true;
        } else if (mem.eql(u8, arg, "--list-themes")) {
            result.list_themes = true;
        } else if (mem.eql(u8, arg, "--demo")) {
            result.demo = true;
        } else if (mem.eql(u8, arg, "--theme") or mem.eql(u8, arg, "-t")) {
            const name = argv.next() orelse {
                try stderr.writeAll("prismacat: --theme needs a name\n");
                return error.InvalidArgs;
            };
            result.theme = prismacat.findTheme(name) orelse {
                try stderr.print("prismacat: unknown theme '{s}'\nknown themes:\n", .{name});
                try prismacat.writeThemeNames(stderr);
                return error.InvalidArgs;
            };
        } else if (mem.eql(u8, arg, "--spread") or mem.eql(u8, arg, "-s")) {
            const value = argv.next() orelse {
                try stderr.writeAll("prismacat: --spread needs a positive integer\n");
                return error.InvalidArgs;
            };
            result.options.spread = std.fmt.parseInt(u16, value, 10) catch {
                try stderr.print("prismacat: invalid spread '{s}'\n", .{value});
                return error.InvalidArgs;
            };
            if (result.options.spread == 0) {
                try stderr.writeAll("prismacat: --spread must be greater than zero\n");
                return error.InvalidArgs;
            }
        } else if (mem.eql(u8, arg, "--angle")) {
            const angle = argv.next() orelse {
                try stderr.writeAll("prismacat: --angle needs 'horizontal' or 'diagonal'\n");
                return error.InvalidArgs;
            };
            if (mem.eql(u8, angle, "horizontal")) {
                result.options.angle = .horizontal;
            } else if (mem.eql(u8, angle, "diagonal")) {
                result.options.angle = .diagonal;
            } else {
                try stderr.print("prismacat: invalid angle '{s}'\n", .{angle});
                return error.InvalidArgs;
            }
        } else {
            try files.append(allocator, arg);
        }
    }

    result.files = files.items;
    return result;
}
