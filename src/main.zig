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

pub const std_options: std.Options = .{
    .log_level = .debug,
};

const nFlakes = 200;

// zig fmt: off
const Context = struct { 
    shm: ?*wl.Shm,
    compositor: ?*wl.Compositor,
    layer_shell: ?*zwlr.LayerShellV1,
    outputs: std.ArrayList(*OutputInfo),
    alloc: std.mem.Allocator,
    running: *bool,
    display: *wl.Display,
};

const OutputInfo = struct {
    output: ?*wl.Output,
    pHeight: u32,
    pWidth: u32,
    name: []const u8,
    uname: u32,
    state: *State,
    alloc: std.mem.Allocator,

    pub fn init(output: ?*wl.Output, name: u32, alloc: std.mem.Allocator) !*OutputInfo{

        const outputInfo: *OutputInfo = try alloc.create(OutputInfo);
        outputInfo.* = OutputInfo{
            .output = output,
            .pWidth = undefined,
            .pHeight = undefined,
            .name = undefined,
            .uname = name,
            .state = undefined,
            .alloc = alloc
        };

        return outputInfo;
    }

    pub fn setName(self: *OutputInfo, name: [*:0]const u8) void {
        const n = self.alloc.alloc(u8, std.mem.len(name)) catch return;
        @memcpy(n, name);
        self.name = n;
    }

    pub fn deinit(self: *OutputInfo) void{
        self.state.deinit();
        self.alloc.free(self.name);
        self.alloc.destroy(self);
    }
};

const State = struct { 
    doubleBuffer: DoubleBuffer,
    surface: *wl.Surface,
    flakes: snow.FlakeArray,
    alloc: std.mem.Allocator,
    missing_flakes: u32,
    running: *const bool,
    outputHeight: u32,
    outputWidth: u32,
    time: ?u32,
    //callBackFunction: fn(cb: *wl.Callback, event: wl.Callback.Event, state: *State) void

    fn init(doubleBuffer: DoubleBuffer, surface: *wl.Surface, running: *bool, outputHeight: u32, outputWidth: u32, alloc: std.mem.Allocator) !*State {
        // zig fmt: off
        const state = try alloc.create(State);
        state.* = State{ 
            .doubleBuffer = doubleBuffer,
            .surface = surface,
            .flakes = try snow.FlakeArray.initCapacity(alloc, nFlakes),
            .alloc = alloc,
            .missing_flakes = nFlakes,
            .running = running,
            .outputHeight = outputHeight,
            .outputWidth = outputWidth,
            .time = null
        };
        // zig fmt: on
        return state;
    }

    fn deinit(self: *State) void {
        self.doubleBuffer.deinit();
        self.flakes.deinit(self.alloc);
        self.surface.destroy();
        self.alloc.destroy(self);
    }
};
// zig fmt: on

fn manageOutput(alloc: std.mem.Allocator, output: *const OutputInfo, context: *Context) !*State {
    const shm = context.shm orelse return error.NoWlShm;
    const compositor = context.compositor orelse return error.NoWlCompositor;
    const layer_shell = context.layer_shell orelse return error.NoLayerShell;

    var doubleBuffer = try DoubleBuffer.init(
        alloc,
        @intCast(output.pWidth),
        @intCast(output.pHeight),
        output.name,
        shm,
    );
    @memset(doubleBuffer.mem(), 0x00000000);
    doubleBuffer.swap();
    @memset(doubleBuffer.mem(), 0x00000000);
    doubleBuffer.swap();

    const surface = try compositor.createSurface();
    const region = try compositor.createRegion();
    surface.setInputRegion(region); // FIXME: This leaks

    // Make a layer surface
    const layer_surface = try layer_shell.getLayerSurface(
        surface,
        output.output,
        zwlr.LayerShellV1.Layer.background,
        "ZSnoW",
    );
    layer_surface.setSize(output.pWidth, output.pHeight);

    const running: *bool = try alloc.create(bool);
    running.* = true;

    // Listen for configure and kill calls
    layer_surface.setListener(*bool, layerSurfaceListener, running);
    surface.commit();
    if (context.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    // Need to attach buffer once to receive frame callbacks
    surface.attach(doubleBuffer.current(), 0, 0);

    // Init rendering via frame callback
    const state = try State.init(doubleBuffer, surface, running, output.pHeight, output.pWidth, alloc);

    // This callback exists once after that it will get destroyed and another starts
    const callback = try surface.frame();
    callback.setListener(*State, frameCallback, state);

    surface.commit();

    return state;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var running = true;

    // zig fmt: off
    var context = Context{ 
        .shm = null,
        .compositor = null,
        .layer_shell = null,
        // .outputs = &outputs,
        .alloc = alloc,
        .running = &running,
        .display = display,
        .outputs = try std.ArrayList(*OutputInfo).initCapacity(alloc, 5)
        };
    // zig fmt: on

    registry.setListener(*Context, registryListener, &context);

    // Blocking roundtrip call to get context
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    // Keep running
    while (running) {
        if (display.dispatch() != .SUCCESS) return error.Dispatchfailed;
    }

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
                
                const outputInfo = OutputInfo.init(output, global.name, context.alloc) 
                    catch { std.debug.print("Cannot create new output\n", .{}); return; };
                context.outputs.append(context.alloc, outputInfo) catch return;
                output.setListener(*Context, outputListener, context);
            }
        },
        .global_remove => |global_remove|{
            std.debug.print("Deregistering output: {}\n", .{global_remove.name});
            var i :usize= 0;
            for (context.outputs.items) |outputInfo|{
                if(outputInfo.uname == global_remove.name){
                    _ = context.outputs.swapRemove(i);
                    outputInfo.output.?.destroy();
                    outputInfo.deinit();
                }
                i += 1;
            }
        },
    }
}

/// Listen to events of our layer surface
// TODO: Pass context instead of running and set correct size
fn layerSurfaceListener(layer_surface: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, running: *bool) void {
    switch (event) {
        .configure => |configure| {
            std.log.debug("Received configure call for layer surface", .{});
            layer_surface.ackConfigure(configure.serial);
        },

        .closed => {
            std.log.info("Received closing call", .{});
            running.* = false;
        }

    }

}

fn outputListener(output: *wl.Output, event: wl.Output.Event, context: *Context) void {
    const outputInfo = blk: {
        for (context.outputs.items) |outputInfoIterated| {
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
        .geometry => |geometry| {
            _ = geometry;
        },
        .mode => |geometry| {
            outputInfo.pHeight = @intCast(geometry.height);
            outputInfo.pWidth = @intCast(geometry.width);
        },

        .name => |name|{
            outputInfo.setName(name.name);
        },

        .done => {
            const state = manageOutput(context.alloc, outputInfo, context)
                catch {std.log.warn("Failed to manage output", .{}); return;};
            outputInfo.state = state;
            std.log.info("Done managing output {s}, size is {}x{}", .{outputInfo.name, outputInfo.pWidth, outputInfo.pHeight});
        },

        else => {},
    }



}


fn frameCallback(cb: *wl.Callback, event: wl.Callback.Event, state: *State) void{
    switch(event){
        .done => {
            if(state.running.*){

                // Calculate time between callbacks
                const currentTimeInMs = event.done.callback_data;
                const timeDelta = currentTimeInMs - (state.time orelse 0);
                state.time = currentTimeInMs;

                // Handle future callbacks
                cb.destroy();
                const cbN = state.surface.frame() catch return;
                cbN.setListener(*State, frameCallback, state);

                // Render the next buffer
                const buffer = state.doubleBuffer.current();
                state.surface.attach(buffer, 0, 0);
                state.surface.damage(0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
                state.surface.commit();

                // Work on the next frame
                state.doubleBuffer.swap();
                const missing = snow.updateFlakes(&state.flakes, state.alloc, state.outputHeight, timeDelta) catch 0;

                const render_init_flakes = state.missing_flakes + missing;
                const missing_flakes = snow.spawnNewFlakes(&state.flakes, state.alloc, render_init_flakes, state.outputWidth) catch 0;
                state.missing_flakes = missing_flakes;
                snow.renderFlakes(&state.flakes, state.doubleBuffer.mem(), state.outputWidth) catch return;
            }
        }
    }
}
