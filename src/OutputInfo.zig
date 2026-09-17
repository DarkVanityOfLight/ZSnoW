const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
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

pub fn init(alloc: std.mem.Allocator, output: *wl.Output, uname: u32) Self {
    return Self{
        .output = output,
        .alloc = alloc,
        .uname = uname,
    };
}

pub fn deinit(self: *Self) void {
    if (self.name) |name|
        self.alloc.free(name);

    self.output.release();
}

pub fn setName(self: *Self, name: [*:0]const u8) !void {
    const replacement = try self.alloc.dupe(u8, std.mem.span(name));
    if (self.name) |old| self.alloc.free(old);
    self.name = replacement;
}
