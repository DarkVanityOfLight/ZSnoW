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
    outputs: std.ArrayList(OutputInfo),
    alloc: std.mem.Allocator,
    display: *wl.Display,
};

/// Initializes required fields in OutputInfo to manage an output
fn manageOutput(output: *OutputInfo, context: *Context) !void {
    try output.activate(context);
    output.missing_flakes = nFlakes;

    // Listen for configure and kill calls
    output.state.?.layer_surface.setListener(*OutputInfo, layerSurfaceListener, output);

    output.state.?.surface.commit();
    if (context.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    // Need to attach buffer once to receive frame callbacks
    output.attachCurrentBuffer();

    // Init rendering via frame callback
    // This callback exists once after that it will get destroyed and another starts
    const callback = try output.state.?.surface.frame();
    callback.setListener(*OutputInfo, frameCallback, output);

    output.state.?.surface.commit();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var running = true;

    var context = Context{
        .shm = null,
        .compositor = null,
        .layer_shell = null,
        .alloc = alloc,
        .display = display,
        .outputs = try std.ArrayList(OutputInfo).initCapacity(alloc, 5),
    };

    registry.setListener(*Context, registryListener, &context);

    // Blocking roundtrip call to finish configure context
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    // Keep running
    while (true) if (display.dispatch() != .SUCCESS) return error.Dispatchfailed;

    // Will never happen rn
    running = false;
    if (display.dispatch() != .SUCCESS) return error.Dispatchfailed;

    _ = gpa.detectLeaks();
}

/// Listen to the registry events, to update collect what we need
fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    // zig fmt: off
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                context.compositor = registry.bind(global.name, wl.Compositor, 6) catch return;

            } else if (mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;

            } else if (mem.orderZ(u8, global.interface, zwlr.LayerShellV1.interface.name) == .eq) {
                context.layer_shell = registry.bind(global.name, zwlr.LayerShellV1, 4) catch return;

            } else if (mem.orderZ(u8, global.interface, wl.Output.interface.name) == .eq){
                const output : *wl.Output = registry.bind(global.name, wl.Output, 4) catch return;
                
                const outputInfo = OutputInfo.init(context.alloc, output, global.name) 
                    catch { std.debug.print("Cannot create new output\n", .{}); return; };
                context.outputs.append(context.alloc, outputInfo) catch return;
                output.setListener(*Context, outputListener, context);
            }
        },
        .global_remove => |global_remove|{
            std.debug.print("Deregistering output: {}\n", .{global_remove.name});
            var i :usize= 0;
            for (context.outputs.items) |*outputInfo|{
                if(outputInfo.uname == global_remove.name){
                    _ = context.outputs.swapRemove(i);
                    outputInfo.output.destroy();
                    outputInfo.deinit();
                    break;
                }
                i += 1;
            }
        },
    }
}

/// Listen to events of our layer surface
// TODO: Pass context instead of running and set correct size
fn layerSurfaceListener(layer_surface: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, output: *OutputInfo) void {
    switch (event) {
        .configure => |configure| {
            std.log.debug("Received configure call for layer surface", .{});
            layer_surface.ackConfigure(configure.serial);
        },

        .closed => {
            std.log.info("Received closing call", .{});
            output.running = false;
        }

    }

}

fn outputListener(output: *wl.Output, event: wl.Output.Event, context: *Context) void {
    const outputInfo = blk: {
        for (context.outputs.items) |*outputInfoIterated| {
            if (output == outputInfoIterated.output) {
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
            outputInfo.height = @intCast(geometry.height);
            outputInfo.width = @intCast(geometry.width);
        },

        .name => |name|{
            outputInfo.setName(name.name);
        },

        .done => {
            manageOutput( outputInfo, context)
                catch {std.log.warn("Failed to manage output", .{}); return;};
            std.log.info("Done managing output {s}, size is {}x{}", .{outputInfo.name, outputInfo.width, outputInfo.height});
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
                cb.destroy();
                const cbN = s.surface.frame() catch return;
                cbN.setListener(*OutputInfo, frameCallback, output);

                output.attachCurrentBuffer();
                s.surface.damage(0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
                s.surface.commit();

                // Calculate time between callbacks
                const currentTimeInMs = event.done.callback_data;
                const timeDelta = currentTimeInMs - (output.time);
                output.time = currentTimeInMs;

                // Work on the next frame
                s.doubleBuffer.swap();


                const missing = snow.updateFlakes(
                &output.flakes,
                output.alloc,
                output.height,
                timeDelta) catch 0;
                const render_init_flakes = output.missing_flakes + missing;

                const missing_flakes = snow.spawnNewFlakes(
                &output.flakes,
                output.alloc,
                render_init_flakes,
                output.width,
                ) catch |err| blk: {
                    std.log.warn("Could not calculate missing flakes {any}", .{err});
                    break :blk 0;    
                };
                output.missing_flakes = missing_flakes;

                snow.renderFlakes(
                &output.flakes,
                s.doubleBuffer.mem(),
                output.width)
                catch return;
            } else std.log.warn("Trying to render unitialized output", .{});
        }
    }
}
