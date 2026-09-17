const std = @import("std");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const setup = @import("waylandsetup.zig").setup;

const snow = @import("snow.zig");
const OutputState = @import("OutputState.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    const context = try setup(alloc, init.io);
    defer {
        context.deinit();
        alloc.destroy(context);
    }

    // Keep running
    while (true) if (context.display.dispatch() != .SUCCESS) return error.Dispatchfailed;
}
