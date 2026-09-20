const std = @import("std");

const Wayland = @import("Wayland.zig");

const zli = @import("zli");

const Config = @import("Config.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn main(init: std.process.Init) !void {
    const root = try Config.cliSetup(init.io, init.gpa, run);
    var args_iter = init.minimal.args.iterate();
    root.runAndExit(&args_iter, .{});
}

fn run(ctx: zli.CommandContext) !void {
    const config = Config.parseCli(ctx);
    const wayland = try Wayland.init(ctx.allocator, ctx.io, config);
    defer {
        wayland.deinit();
        ctx.allocator.destroy(wayland);
    }

    // Keep running
    while (true) if (wayland.display.dispatch() != .SUCCESS) return error.Dispatchfailed;
}
