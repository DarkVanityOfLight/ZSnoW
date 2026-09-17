const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const DoubleBuffer = @import("DoubleBuffer.zig");
const snow = @import("snow.zig");
const Context = @import("main.zig").Context;
const Flake = @import("flakes/flake.zig").Flake;

const zwlr = wayland.client.zwlr;
const Self = @This();

// Persistent
output: *wl.Output,
uname: u32,
// Defaultet
height: u32 = 0,
width: u32 = 0,
mode_height: u32 = 0,
mode_width: u32 = 0,
swap_dimensions: bool = false,
time: u32 = 0,
running: bool = true,
scale: i32 = 1,
name: ?[]const u8 = null,

alloc: std.mem.Allocator,

pub fn init(alloc: std.mem.Allocator, output: *wl.Output, uname: u32) !Self {
    return Self{
        .output = output,
        .alloc = alloc,
        .uname = uname,
    };
}

pub fn deinit(self: *Self) void {
    if (self.name) |name|
        self.alloc.free(name);

    self.output.destroy();
}

pub fn setName(self: *Self, name: [*:0]const u8) !void {
    const n = try self.alloc.alloc(u8, std.mem.len(name));
    @memcpy(n, name);
    self.name = n;
}
