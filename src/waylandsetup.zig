//! Output and layer-surface lifecycle
//!
//! 1. setup() connects to Wayland and installs registryListener. Registry
//!    globals provide the compositor, shared-memory interface, layer shell,
//!    and outputs. The event loop continues dispatching events after setup.
//!
//! 2. An output global calls addOutput(): bind wl_output, initialize OutputState
//!    (metadata and snow system, activeState = null), add it to Context.outputs,
//!    then register configureOutput. The state exists before its events arrive.
//!
//! 3. configureOutput collects mode, scale, geometry, and name events. A matching
//!    ignored name calls removeOutput and returns immediately: removal frees the
//!    state, even if it has never created a layer surface. Each name check uses
//!    a copy of the ignore iterator so it checks the full list.
//!
//! 4. wl_output.done calls manageOutput(), which deactivates any old surface,
//!    then activates a new one. activate() creates the wl_surface, layer surface,
//!    and buffers, with configured = false. manageOutput installs the layer
//!    listener and commits without attaching a buffer to begin configuration.
//!    Output configuration and layer-surface configuration are separate stages.
//!
//! 5. layerSurfaceListener receives the layer surface's configure event and
//!    acknowledges its serial. The current handler attaches the initial buffer,
//!    requests a frame callback, and commits. It repeats this on every configure;
//!    requestFrame prevents duplicate outstanding callbacks. Currently configured
//!    is initialized to false but never read or set true: it does not yet gate
//!    this startup path. Configure dimensions are also currently ignored in
//!    favor of the output mode dimensions.
//!
//! 6. animation.frameCallback clears and destroys the completed callback, updates
//!    snow, and renders into the next buffer if it is free. It attaches the
//!    current buffer, damages the surface, requests the next callback, and commits.
//!    Buffer release events separately mark buffers available for reuse.
//!
//! 7. Another wl_output.done repeats manageOutput(), destroying and recreating
//!    rendering resources and restarting layer-surface configuration. A later
//!    layer-surface configure alone does not recreate those resources.
//!
//! 8. layer-surface.closed calls deactivate(): stop animation, destroy any pending
//!    frame callback, buffers, region, and surfaces, then set activeState = null.
//!    The OutputState remains registered. Registry global_remove instead calls
//!    removeOutput(): remove the list entry, deactivate, release output metadata
//!    and wl_output, free the snow system, and destroy the state. Context.deinit()
//!    similarly cleans up all remaining outputs before disconnecting Wayland.
//!
//! Lifetime rule: activeState may be null while OutputState is still alive.
//! configured belongs to a particular surface instance, not to output discovery.
//! After removeOutput(), neither OutputState nor pointers into its info are valid.

const std = @import("std");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const OutputState = @import("OutputState.zig");
const animation = @import("animation.zig");

const CliContext = @import("main.zig").CliContext;

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
    cli_context: CliContext,

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

fn createContext(alloc: std.mem.Allocator, io: std.Io, cli_context: CliContext) !*Context {
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
        .cli_context = cli_context,
    };
    return context;
}

pub fn setup(alloc: std.mem.Allocator, io: std.Io, cli_context: CliContext) !*Context {
    const context = try createContext(alloc, io, cli_context);
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
    outputState.* = try OutputState.init(
        context.alloc,
        context.io,
        output,
        name,
        nFlakes,
    );
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
            std.log.debug("Received configure call for layer surface: {any}", .{configure});
            layer_surface.ackConfigure(configure.serial);

            if(output.activeState.?.configured) return;

            // Need to attach buffer once to receive frame callbacks
            output.attachCurrentBuffer();
            animation.requestFrame(output) catch return;
            output.activeState.?.surface.commit();
            output.activeState.?.configured = true;
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
              var ignored = context.cli_context.ignored_outputs;
              while (ignored.next()) |candidate| {
                  if (mem.eql(u8, candidate, mem.span(name.name))) {
                      removeOutput(context, outputInfo.uname);
                      return;
                  }
              }
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
