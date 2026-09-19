const std = @import("std");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const setup = @import("waylandsetup.zig").setup;
const zli = @import("zli");

const snow = @import("snow.zig");
const OutputState = @import("OutputState.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub const CliContext = struct {
    ignored_outputs: std.mem.TokenIterator(u8, .scalar),
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var wbuf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.Writer.init(.stdout(), io, &wbuf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var rbuf: [1024]u8 = undefined;
    var stdin_reader = std.Io.File.Reader.init(.stdin(), io, &rbuf);
    const stdin = &stdin_reader.interface;

    const init_options = zli.InitOptions{
        .allocator = init.gpa,
        .io = io,
        .writer = stdout,
        .reader = stdin,
    };

    const root = try zli.Command.init(
        init_options,
        .{
            .name = "ZsnoW",
            .description = "Xsnow on Wayland",
            .version = .{ .major = 0, .minor = 1, .patch = 0, .pre = null, .build = null },
        },
        run,
    );

    try root.addFlag(.{
        .name = "ignore",
        .description = "Ignore an output, comma separated values OUT-1,OUT-2 ...",
        .type = .String,
        .default_value = .{ .String = "" },
    });

    try root.addCommands(&.{});
    var args_iter = init.minimal.args.iterate();
    root.runAndExit(&args_iter, .{});
}

fn run(ctx: zli.CommandContext) !void {
    const s = ctx.flag("ignore", []const u8);
    const outputs = std.mem.tokenizeScalar(u8, s, ',');

    const cli_context: CliContext = .{
        .ignored_outputs = outputs,
    };

    const context = try setup(ctx.allocator, ctx.io, cli_context);
    defer {
        context.deinit();
        ctx.allocator.destroy(context);
    }

    // Keep running
    while (true) if (context.display.dispatch() != .SUCCESS) return error.Dispatchfailed;
}
