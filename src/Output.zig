const std = @import("std");
const SnowSystem = @import("SnowSystem.zig");
const DoubleBuffer = @import("DoubleBuffer.zig");
// const Context = @import("waylandsetup.zig").Context;

const Wayland = @import("Wayland.zig");
const wl = @import("wayland").client.wl;
const zwlr = @import("wayland").client.zwlr;

const Self = @This();

const ActiveState = struct {
    surface: *wl.Surface,
    input_region: *wl.Region,
    layer_surface: *zwlr.LayerSurfaceV1,
    doubleBuffer: ?DoubleBuffer = null,
    frame_callback: ?*wl.Callback = null,
    configured: bool,
};

output: *wl.Output,

uname: u32,
height: u32 = 0,
width: u32 = 0,
scale: i32 = 1,

name: ?[]const u8 = null,
time: u32 = 0,
running: bool = true,

snowSystem: SnowSystem,
activeState: ?ActiveState = null,
alloc: std.mem.Allocator,

// These fields should be refactored away
io: std.Io,
shm: *wl.Shm,

/// Takes ownership of output only on success. Keep this state at a stable
/// address once activated: Wayland listeners refer to it and its buffers.
pub fn init(alloc: std.mem.Allocator, io: std.Io, output: *wl.Output, name: u32, flake_count: u32, shm: *wl.Shm) !Self {
    return .{
        .output = output,
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
    std.debug.assert(self.activeState == null);

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
    layer_surface.setAnchor(.{
        .top = true,
        .bottom = true,
        .left = true,
        .right = true,
    });
    layer_surface.setSize(0, 0);

    self.activeState = ActiveState{
        .surface = surface,
        .input_region = input_region,
        .layer_surface = layer_surface,
        .configured = false,
    };
    self.running = true;
}

pub fn deactivate(self: *Self) void {
    self.running = false;
    if (self.activeState) |*s| {
        if (s.frame_callback) |cb| {
            cb.destroy();
            s.frame_callback = null;
        }
        if (s.doubleBuffer) |*db|
            db.deinit();
        s.input_region.destroy();
        s.layer_surface.destroy();
        s.surface.destroy();

        self.activeState = null;
    }
}

pub fn attachCurrentBuffer(self: *Self) void {
    self.activeState.?.doubleBuffer.?.attach(self.activeState.?.surface);
}

pub fn applyConfiguration(self: *Self, context: *Wayland) !void {
    self.deactivate();
    try self.activate(context.compositor.?, context.layer_shell.?);
}

pub fn deinit(self: *Self) void {
    self.deactivate();

    if (self.name) |name|
        self.alloc.free(name);

    self.output.release();

    self.snowSystem.deinit();
}
