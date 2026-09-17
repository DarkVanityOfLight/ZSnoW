const std = @import("std");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const OutputState = @import("OutputState.zig");
const animation = @import("animation.zig");

const nFlakes = 200;

pub const Context = struct {
    shm: ?*wl.Shm,
    compositor: ?*wl.Compositor,
    layer_shell: ?*zwlr.LayerShellV1,
    outputs: std.ArrayList(*OutputState),
    alloc: std.mem.Allocator,
    io: std.Io,
    display: *wl.Display,
    registry: *wl.Registry,

    pub fn deinit(self: *Context) void {
        for (self.outputs.items) |output| {
            output.deinit();
            self.alloc.destroy(output);
        }
        self.outputs.deinit(self.alloc);
        if (self.layer_shell) |shell| shell.destroy();
        if (self.shm) |shm| shm.destroy();
        if (self.compositor) |compositor| compositor.destroy();
        self.registry.destroy();
        self.display.disconnect();
    }
};

fn createContext(alloc: std.mem.Allocator, io: std.Io) !*Context {
    const display = try wl.Display.connect(null);
    errdefer display.disconnect();

    const registry = try display.getRegistry();
    errdefer registry.destroy();

    const context = try alloc.create(Context);
    errdefer alloc.destroy(context);
    context.* = Context{
        .shm = null,
        .compositor = null,
        .layer_shell = null,
        .alloc = alloc,
        .outputs = try std.ArrayList(*OutputState).initCapacity(alloc, 5),
        .io = io,
        .display = display,
        .registry = registry,
    };
    return context;
}

pub fn setup(alloc: std.mem.Allocator, io: std.Io) !*Context {
    const context = try createContext(alloc, io);
    errdefer {
        context.deinit();
        alloc.destroy(context);
    }
    context.registry.setListener(*Context, registryListener, context);

    // Blocking roundtrip call to finish configure context
    if (context.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    return context;
}

/// Initializes required fields in OutputInfo to manage an output
fn manageOutput(output: *OutputState, context: *Context) !void {
    // Deactivate old if exists
    output.deactivate();
    try output.activate(context);

    output.snowSystem.resetFlakesTo(nFlakes);

    // Listen for configure and kill calls
    output.activeState.?.layer_surface.setListener(*OutputState, layerSurfaceListener, output);

    output.activeState.?.surface.commit();
}

fn isInterface(interface: [*:0]const u8, comptime T: type) bool {
    return mem.orderZ(u8, interface, T.interface.name) == .eq;
}

fn addOutput(
    context: *Context,
    registry: *wl.Registry,
    name: u32,
) !void {
    // Reserve the list entry before acquiring resources so registration cannot
    // fail after ownership has transferred to OutputState.
    try context.outputs.ensureUnusedCapacity(context.alloc, 1);
    const outputState = try context.alloc.create(OutputState);
    errdefer context.alloc.destroy(outputState);

    const output = try registry.bind(name, wl.Output, 4);
    errdefer output.release();
    outputState.* = try OutputState.init(context.alloc, context.io, output, name, nFlakes);
    context.outputs.appendAssumeCapacity(outputState);

    output.setListener(*Context, configureOutput, context);
}

fn removeOutput(context: *Context, name: u32) void {
    for (context.outputs.items, 0..) |state, i| {
        const info = state.info;
        if (info.uname != name)
            continue;

        _ = context.outputs.swapRemove(i);

        state.deinit();
        context.alloc.destroy(state);
        return;
    }
}

/// Listen to the registry events, to update collect what we need
fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    // zig fmt: off
    switch (event) {
        .global => |global| {
            if (isInterface(global.interface, wl.Compositor)) {
                context.compositor = registry.bind(global.name, wl.Compositor, 6) catch return;

            } else if (isInterface(global.interface, wl.Shm)) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;

            } else if (isInterface(global.interface, zwlr.LayerShellV1)) {
                context.layer_shell = registry.bind(global.name, zwlr.LayerShellV1, 4) catch return;

            } else if (isInterface(global.interface, wl.Output)) {
                addOutput(context, registry, global.name) catch |err| {
                    std.log.err("Failed to register output: {}", .{err});
                };
            }
        },
        .global_remove => |global|{
            std.log.debug("Deregistering output: {}", .{global.name});
            removeOutput(context, global.name);
        },
    }
}

/// Listen to events of our layer surface
fn layerSurfaceListener(layer_surface: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, output: *OutputState) void {
    switch (event) {
        .configure => |configure| {
            std.log.debug("Received configure call for layer surface", .{});
            layer_surface.ackConfigure(configure.serial);

            // Need to attach buffer once to receive frame callbacks
            output.attachCurrentBuffer();
            animation.requestFrame(output) catch return;
            output.activeState.?.surface.commit();
        },

        .closed => {
            std.log.info("Received closing call", .{});
            output.deactivate();
        }

    }

}

fn configureOutput(output: *wl.Output, event: wl.Output.Event, context: *Context) void {
    // Find the correct output to configure
    const outputState = blk: {
        for (context.outputs.items) |outputStateIterated| {
            if (output == outputStateIterated.info.output) {
                break :blk outputStateIterated;
            }
        }
        std.log.warn("Received unmanaged output", .{});
        return;
    };
    const outputInfo = &outputState.info;


    // Configure
    std.log.debug("Event {s} on output: {}", .{@tagName(event), outputInfo.uname});
    switch (event) {
        .mode => |geometry| {
            if (!geometry.flags.current) return;

            outputInfo.mode_height = @intCast(geometry.height);
            outputInfo.mode_width = @intCast(geometry.width);
        },

        .name => |name|{
            outputInfo.setName(name.name) catch |err| {
                std.log.warn("Failed to set name: {any}", .{err});
            };
        },

        .scale => |scale| {
            outputInfo.scale = scale.factor;
        },

        .geometry => |geometry|{
            outputInfo.swap_dimensions = switch (geometry.transform) {
                .@"90", .@"270", .flipped_90, .flipped_270 => true,
                else => false,
            };
        },

        .done => {
            // Derive dimensions from the mode once all output events have arrived.
            outputInfo.width = if (outputInfo.swap_dimensions) outputInfo.mode_height else outputInfo.mode_width;
            outputInfo.height = if (outputInfo.swap_dimensions) outputInfo.mode_width else outputInfo.mode_height;
            manageOutput(outputState, context) catch {std.log.warn("Failed to configure output", .{}); return;};
            std.log.info("Done managing output {s}, size is {}x{}", .{outputInfo.name orelse "unnamed", outputInfo.width, outputInfo.height});
        },

        else => {},
    }



}
