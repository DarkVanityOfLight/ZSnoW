const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zwlr = wayland.client.zwlr;

const flakes = @import("flakes/flake.zig");
const snow = @import("snow.zig");
const DoubleBuffer = @import("DoubleBuffer.zig");
const OutputInfo = @import("OutputInfo.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

const nFlakes = 200;

pub const Context = struct {
    shm: ?*wl.Shm,
    compositor: ?*wl.Compositor,
    layer_shell: ?*zwlr.LayerShellV1,
    outputs: std.ArrayList(*OutputInfo),
    alloc: std.mem.Allocator,
    display: *wl.Display,
    io: std.Io,
};

/// Initializes required fields in OutputInfo to manage an output
fn manageOutput(output: *OutputInfo, context: *Context) !void {
    // Deactivate old if exists
    output.deactivate();
    try output.activate(context);

    output.resetFlakesTo(nFlakes);

    // Listen for configure and kill calls
    output.state.?.layer_surface.setListener(*OutputInfo, layerSurfaceListener, output);

    output.state.?.surface.commit();
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var running = true;

    var context = Context{
        .shm = null,
        .compositor = null,
        .layer_shell = null,
        .alloc = alloc,
        .display = display,
        .outputs = try std.ArrayList(*OutputInfo).initCapacity(alloc, 5),
        .io = init.io,
    };

    registry.setListener(*Context, registryListener, &context);

    // Blocking roundtrip call to finish configure context
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    // Keep running
    while (true) if (display.dispatch() != .SUCCESS) return error.Dispatchfailed;

    // Will never happen rn
    running = false;
    if (display.dispatch() != .SUCCESS) return error.Dispatchfailed;
}

fn isInterface(interface: [*:0]const u8, comptime T: type) bool {
    return mem.orderZ(u8, interface, T.interface.name) == .eq;
}

fn addOutput(
    context: *Context,
    registry: *wl.Registry,
    name: u32,
) !void {
    const output = try registry.bind(name, wl.Output, 4);
    errdefer output.release();

    const info = try context.alloc.create(OutputInfo);
    errdefer context.alloc.destroy(info);

    info.* = try OutputInfo.init(
        context.alloc,
        context.io,
        output,
        name,
    );
    errdefer info.deinit();

    try context.outputs.append(context.alloc, info);

    output.setListener(*Context, outputListener, context);
}

fn removeOutput(context: *Context, name: u32) void {
    for (context.outputs.items, 0..) |info, i| {
        if (info.uname != name)
            continue;

        _ = context.outputs.swapRemove(i);

        info.deinit();
        context.alloc.destroy(info);
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
fn layerSurfaceListener(layer_surface: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, output: *OutputInfo) void {
    switch (event) {
        .configure => |configure| {
            std.log.debug("Received configure call for layer surface", .{});
            layer_surface.ackConfigure(configure.serial);

            // Need to attach buffer once to receive frame callbacks
            output.attachCurrentBuffer();

            if(output.state.?.frame_callback == null) {
                // Init rendering via frame callback
                // This callback exists once after that it will get destroyed and another starts
                const callback = output.state.?.surface.frame() catch return;
                callback.setListener(*OutputInfo, frameCallback, output);
                output.state.?.frame_callback = callback;
            }
            output.state.?.surface.commit();
        },

        .closed => {
            std.log.info("Received closing call", .{});
            output.running = false;
        }

    }

}

fn outputListener(output: *wl.Output, event: wl.Output.Event, context: *Context) void {
    const outputInfo = blk: {
        for (context.outputs.items) |outputInfoIterated| {
            if (output == outputInfoIterated.*.output) {
                break :blk outputInfoIterated;
            }
        }
        std.log.warn("Received unmanaged output", .{});
        return;
    };

    // std.debug.print("Info {?}\n", .{outputInfoNull});

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
            manageOutput(outputInfo, context) catch {std.log.warn("Failed to configure output", .{}); return;};
            std.log.info("Done managing output {s}, size is {}x{}", .{outputInfo.name orelse "unnamed", outputInfo.width, outputInfo.height});
        },

        else => {},
    }



}


fn frameCallback(cb: *wl.Callback, event: wl.Callback.Event, output: *OutputInfo) void{
    switch(event){
        .done => {
            if (!output.running) return;

            if (output.state) |*s|{
                // Handle future callbacks
                s.frame_callback = null;
                cb.destroy();

                const cbN = s.surface.frame() catch |err| {
                    std.log.err("Cannot schedule animation frame: {s}", .{@errorName(err)});
                    output.running = false;
                    return;
                };

                cbN.setListener(*OutputInfo, frameCallback, output);
                s.frame_callback = cbN;

                output.attachCurrentBuffer();
                s.surface.damage(0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
                s.surface.commit();

                // Calculate time between callbacks
                const currentTimeInMs = event.done.callback_data;
                const timeDelta = currentTimeInMs -% (output.time);
                output.time = currentTimeInMs;

                const removed = snow.updateFlakes(
                &output.flakes,
                output.alloc,
                output.height,
                timeDelta);
                const render_init_flakes = output.missing_flakes + removed;

                const missing_flakes = snow.spawnNewFlakes(
                output.prng.random(),
                &output.flakes,
                output.alloc,
                render_init_flakes,
                output.width,
                ) catch |err| blk: {
                    std.log.warn("Could not calculate missing flakes {any}", .{err});
                    break :blk 0;    
                };
                output.missing_flakes = missing_flakes;


                // Work on the next frame if buffer is free
                if (!s.doubleBuffer.swap()) 
                    return;

                snow.renderFlakes(
                &output.flakes,
                s.doubleBuffer.mem(),
                output.width)
                catch return;
            } else std.log.warn("Trying to render unitialized output", .{});
        }
    }
}
