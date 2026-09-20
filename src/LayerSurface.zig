const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const DoubleBuffer = @import("DoubleBuffer.zig");
const Output = @import("Output.zig");
const animation = @import("animation.zig");

const Self = @This();

surface: *wl.Surface,
input_region: *wl.Region,
layer_surface: *zwlr.LayerSurfaceV1,
doubleBuffer: ?DoubleBuffer = null,
frame_callback: ?*wl.Callback = null,
configured: bool,
output: *Output,

pub fn init(compositor: *wl.Compositor, layer_shell: *zwlr.LayerShellV1, output: *Output, scale: i32) !Self {
    // std.debug.assert(self.activeState == null);

    // Create a surface
    const surface = try compositor.createSurface();
    errdefer surface.destroy();
    surface.setBufferScale(scale);

    // Set input region none
    const input_region = try compositor.createRegion();
    errdefer input_region.destroy();
    surface.setInputRegion(input_region);

    // Make it a layer surface
    const layer_surface = try layer_shell.getLayerSurface(
        surface,
        output.wl_output,
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

    return .{
        .surface = surface,
        .input_region = input_region,
        .layer_surface = layer_surface,
        .configured = false,
        .output = output,
    };
}

pub fn listen(self: *Self) void {
    // output.activeState.?.layer_surface.setListener(*Output, layerSurfaceListener, output);
    self.layer_surface.setListener(*Self, listener, self);
    self.surface.commit();
}

fn listener(layer_surface: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, self: *Self) void {
    switch (event) {
        .configure => |configure| {
            std.log.debug("Received configure call for layer surface: {any}", .{configure});
            layer_surface.ackConfigure(configure.serial);

            if (self.output.height == event.configure.height and
                self.output.width == event.configure.width and
                self.doubleBuffer != null) return;

            const scale: u32 = @intCast(self.output.scale);
            const buffer_width = configure.width * scale;
            const buffer_height = configure.height * scale;
            const replacement = DoubleBuffer.init(
                self.output.io,
                buffer_width,
                buffer_height,
                self.output.name orelse "ZSnoW",
                self.output.shm,
            ) catch |err| {
                std.log.err("Failed to create buffers: {s}", .{@errorName(err)});
                return;
            };

            if (self.doubleBuffer) |*old| old.deinit();
            self.doubleBuffer = replacement;
            self.doubleBuffer.?.listen();

            self.output.height = configure.height;
            self.output.width = configure.width;

            if (self.configured) return;

            // Need to attach buffer once to receive frame callbacks
            self.output.attachCurrentBuffer();
            animation.requestFrame(self.output) catch return;
            self.surface.commit();
            self.configured = true;
        },

        .closed => {
            std.log.info("Received closing call", .{});
            self.output.deactivate();
        },
    }
}

pub fn deinit(self: *Self) void {
    if (self.frame_callback) |cb| {
        cb.destroy();
        self.frame_callback = null;
    }
    if (self.doubleBuffer) |*db|
        db.deinit();
    self.input_region.destroy();
    self.layer_surface.destroy();
    self.surface.destroy();
}
