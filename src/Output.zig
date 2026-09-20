const std = @import("std");
const SnowSystem = @import("SnowSystem.zig");
const DoubleBuffer = @import("DoubleBuffer.zig");
// const Context = @import("waylandsetup.zig").Context;

const Wayland = @import("Wayland.zig");
const LayerSurface = @import("LayerSurface.zig");
const wl = @import("wayland").client.wl;
const zwlr = @import("wayland").client.zwlr;

const Self = @This();

wl_output: *wl.Output,

uname: u32,
height: u32 = 0,
width: u32 = 0,
scale: i32 = 1,

name: ?[]const u8 = null,
time: u32 = 0,
running: bool = true,

snowSystem: SnowSystem,
layer_surface: ?LayerSurface = null,
alloc: std.mem.Allocator,

// These fields should be refactored away
io: std.Io,
shm: *wl.Shm,

/// Takes ownership of output only on success. Keep this state at a stable
/// address once activated: Wayland listeners refer to it and its buffers.
pub fn init(alloc: std.mem.Allocator, io: std.Io, wl_output: *wl.Output, name: u32, flake_count: u32, shm: *wl.Shm) !Self {
    return .{
        .wl_output = wl_output,
        .uname = name,
        .snowSystem = try SnowSystem.init(alloc, io, flake_count),
        .alloc = alloc,
        .io = io,
        .shm = shm,
    };
}

pub fn setName(self: *Self, name: [*:0]const u8) !void {
    const replacement = try self.alloc.dupe(u8, std.mem.span(name));
    if (self.name) |old| self.alloc.free(old);
    self.name = replacement;
}

pub fn activate(self: *Self, compositor: *wl.Compositor, layer_shell: *zwlr.LayerShellV1) !void {
    self.layer_surface = try LayerSurface.init(
        compositor,
        layer_shell,
        self,
        self.scale,
    );
    self.running = true;
    self.layer_surface.?.listen();
}

pub fn deactivate(self: *Self) void {
    self.running = false;
    if (self.layer_surface) |*s| {
        s.deinit();
        self.layer_surface = null;
    }
}

pub fn attachCurrentBuffer(self: *Self) void {
    self.layer_surface.?.doubleBuffer.?.attach(self.layer_surface.?.surface);
}

pub fn applyConfiguration(self: *Self, context: *Wayland) !void {
    self.deactivate();
    try self.activate(context.compositor.?, context.layer_shell.?);
}

pub fn deinit(self: *Self) void {
    self.deactivate();

    if (self.name) |name|
        self.alloc.free(name);

    self.wl_output.release();

    self.snowSystem.deinit();
}
