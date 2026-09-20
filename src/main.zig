const std = @import("std");

const Wayland = @import("Wayland.zig");

const zli = @import("zli");

const Config = @import("Config.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn main(init: std.process.Init) !void {
    var wbuf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.Writer.init(.stdout(), init.io, &wbuf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var rbuf: [1024]u8 = undefined;
    var stdin_reader = std.Io.File.Reader.init(.stdin(), init.io, &rbuf);
    const stdin = &stdin_reader.interface;

    const root = try Config.cliSetup(init.io, init.gpa, stdin, stdout, run);
    var args_iter = init.minimal.args.iterate();
    root.runAndExit(&args_iter, .{});
}

fn run(ctx: zli.CommandContext) !void {
    const config = try Config.parseCli(ctx);
    const wayland = try Wayland.init(ctx.allocator, ctx.io, config);
    defer {
        wayland.deinit();
        ctx.allocator.destroy(wayland);
    }

    // Keep running
    while (true) if (wayland.display.dispatch() != .SUCCESS) return error.Dispatchfailed;
}
