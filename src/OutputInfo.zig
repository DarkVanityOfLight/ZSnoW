const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const DoubleBuffer = @import("DoubleBuffer.zig");
const snow = @import("snow.zig");
const Context = @import("main.zig").Context;
const Flake = @import("flakes/flake.zig").Flake;

const zwlr = wayland.client.zwlr;
const Self = @This();

const ActiveState = struct {
    surface: *wl.Surface,
    input_region: *wl.Region,
    layer_surface: *zwlr.LayerSurfaceV1,
    doubleBuffer: DoubleBuffer,
    frame_callback: ?*wl.Callback = null,
};

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

state: ?ActiveState = null,

alloc: std.mem.Allocator,

pub fn init(alloc: std.mem.Allocator, output: *wl.Output, uname: u32) !Self {
    return Self{
        .output = output,
        .alloc = alloc,
        .uname = uname,
    };
}

pub fn activate(self: *Self, context: *Context) !void {
    // Create backed memory
    const shm = context.shm orelse return error.NoWlShm;
    const compositor = context.compositor orelse return error.NoWlCompositor;
    const layer_shell = context.layer_shell orelse return error.NoLayerShell;

    // Create a surface
    const surface = try compositor.createSurface();
    errdefer surface.destroy();
    surface.setBufferScale(self.scale);

    // Set input region none
    const input_region = try compositor.createRegion();
    errdefer input_region.destroy();
    surface.setInputRegion(input_region);

    // Make it a layer surface
    const layer_surface = try layer_shell.getLayerSurface(
        surface,
        self.output,
        zwlr.LayerShellV1.Layer.background,
        "ZSnoW",
    );
    errdefer layer_surface.destroy();
    layer_surface.setSize(self.width, self.height);

    self.state = ActiveState{
        .surface = surface,
        .input_region = input_region,
        .layer_surface = layer_surface,
        .doubleBuffer = try DoubleBuffer.init(context.io, self.width, self.height, self.name.?, shm),
    };
    self.running = true;
    self.state.?.doubleBuffer.listen();
}

pub fn deactivate(self: *Self) void {
    if (self.state) |*s| {
        if (s.frame_callback) |cb| {
            cb.destroy();
            s.frame_callback = null;
        }
        s.doubleBuffer.deinit();
        s.input_region.destroy();
        s.layer_surface.destroy();
        s.surface.destroy();

        self.state = null;
    }
}

pub fn deinit(self: *Self) void {
    self.deactivate();

    if (self.name) |name|
        self.alloc.free(name);

    self.output.destroy();
}

pub fn attachCurrentBuffer(self: *Self) void {
    self.state.?.doubleBuffer.attach(self.state.?.surface);
}

pub fn setName(self: *Self, name: [*:0]const u8) !void {
    const n = try self.alloc.alloc(u8, std.mem.len(name));
    @memcpy(n, name);
    self.name = n;
}

pub fn applyConfiguration(self: *Self, context: *Context) !void {
    self.deactivate();
    try self.activate(context);
}
