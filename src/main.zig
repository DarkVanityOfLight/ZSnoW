const std = @import("std");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const setup = @import("waylandsetup.zig").setup;
const zli = @import("zli");

const snow = @import("snow.zig");
const OutputState = @import("OutputState.zig");
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
    const context = try setup(ctx.allocator, ctx.io, config);
    defer {
        context.deinit();
        ctx.allocator.destroy(context);
    }

    // Keep running
    while (true) if (context.display.dispatch() != .SUCCESS) return error.Dispatchfailed;
}
