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
};

// Persistent
output: *wl.Output,
name: []const u8 = "",
uname: u32,
flakes: snow.FlakeArray,
// Defaultet
height: u32 = 0,
width: u32 = 0,
missing_flakes: u32 = 0,
time: u32 = 0,

state: ?ActiveState = null,

alloc: std.mem.Allocator,

pub fn init(alloc: std.mem.Allocator, output: *wl.Output, uname: u32) !Self {
    return Self{
        .output = output,
        .alloc = alloc,
        .uname = uname,
        .flakes = std.ArrayList(*Flake).empty,
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
    const input_region = try compositor.createRegion();
    surface.setInputRegion(input_region);

    // Make it a layer surface
    const layer_surface = try layer_shell.getLayerSurface(
        surface,
        self.output,
        zwlr.LayerShellV1.Layer.background,
        "ZSnoW",
    );
    layer_surface.setSize(self.width, self.height);

    self.state = ActiveState{
        .surface = surface,
        .input_region = input_region,
        .layer_surface = layer_surface,
        .doubleBuffer = try DoubleBuffer.init(self.width, self.height, self.name, shm),
    };
}

pub fn deinit(self: *Self) void {
    self.alloc.free(self.name);
    self.flakes.deinit(self.alloc);
    if (self.state) |*s| {
        s.surface.destroy();
        s.doubleBuffer.deinit();
        s.layer_surface.destroy();
        s.input_region.destroy();
    }
    self.output.destroy();
}

pub fn attachCurrentBuffer(self: *Self) void {
    self.state.?.surface.attach(self.state.?.doubleBuffer.current(), 0, 0);
}

pub fn setName(self: *Self, name: [*:0]const u8) void {
    const n = self.alloc.alloc(u8, std.mem.len(name)) catch return;
    @memcpy(n, name);
    self.name = n;
}
