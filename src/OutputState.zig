const OutputInfo = @import("OutputInfo.zig");
const SnowSystem = @import("SnowSystem.zig");
const DoubleBuffer = @import("DoubleBuffer.zig");
const Context = @import("main.zig").Context;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

const Self = @This();

const ActiveState = struct {
    surface: *wl.Surface,
    input_region: *wl.Region,
    layer_surface: *zwlr.LayerSurfaceV1,
    doubleBuffer: DoubleBuffer,
    frame_callback: ?*wl.Callback = null,
};

info: OutputInfo,
snowSystem: SnowSystem,
activeState: ?ActiveState = null,

pub fn activate(self: *Self, context: *Context) !void {
    // Create backed memory
    const shm = context.shm orelse return error.NoWlShm;
    const compositor = context.compositor orelse return error.NoWlCompositor;
    const layer_shell = context.layer_shell orelse return error.NoLayerShell;

    // Create a surface
    const surface = try compositor.createSurface();
    errdefer surface.destroy();
    surface.setBufferScale(self.info.scale);

    // Set input region none
    const input_region = try compositor.createRegion();
    errdefer input_region.destroy();
    surface.setInputRegion(input_region);

    // Make it a layer surface
    const layer_surface = try layer_shell.getLayerSurface(
        surface,
        self.info.output,
        zwlr.LayerShellV1.Layer.background,
        "ZSnoW",
    );
    errdefer layer_surface.destroy();
    layer_surface.setSize(self.info.width, self.info.height);

    self.activeState = ActiveState{
        .surface = surface,
        .input_region = input_region,
        .layer_surface = layer_surface,
        .doubleBuffer = try DoubleBuffer.init(
            context.io,
            self.info.width,
            self.info.height,
            self.info.name.?,
            shm,
        ),
    };
    self.info.running = true;
    self.activeState.?.doubleBuffer.listen();
}

pub fn deactivate(self: *Self) void {
    if (self.activeState) |*s| {
        if (s.frame_callback) |cb| {
            cb.destroy();
            s.frame_callback = null;
        }
        s.doubleBuffer.deinit();
        s.input_region.destroy();
        s.layer_surface.destroy();
        s.surface.destroy();

        self.activeState = null;
    }
}

pub fn attachCurrentBuffer(self: *Self) void {
    self.activeState.?.doubleBuffer.attach(self.activeState.?.surface);
}

pub fn applyConfiguration(self: *Self, context: *Context) !void {
    self.deactivate();
    try self.activate(context);
}

pub fn deinit(self: *Self) void {
    self.deactivate();
    self.info.deinit();
    self.snowSystem.deinit();
}
