const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const Output = @import("Output.zig");

const Config = @import("Config.zig");

const Self = @This();

shm: ?*wl.Shm,
compositor: ?*wl.Compositor,
layer_shell: ?*zwlr.LayerShellV1,
display: *wl.Display,
registry: *wl.Registry,

outputs: std.ArrayList(*Output),
pending_outputs: std.ArrayList(u32) = .empty,
ready: bool = false,
discovery_error: ?anyerror = null,

config: Config,
alloc: std.mem.Allocator,
io: std.Io,

//Helpers
fn isInterface(interface: [*:0]const u8, comptime T: type) bool {
    return std.mem.orderZ(u8, interface, T.interface.name) == .eq;
}

fn isIgnored(
    outputName: [*:0]const u8,
    outputs: std.mem.TokenIterator(u8, .scalar),
) bool {
    var iter = outputs;
    while (iter.next()) |candidate| {
        if (std.mem.eql(u8, candidate, std.mem.span(outputName))) {
            return true;
        }
    }
    return false;
}

fn findOutput(self: *Self, wl_output: *wl.Output) ?*Output {
    for (self.outputs.items) |output| {
        if (wl_output == output.wl_output) {
            return output;
        }
    }
    return null;
}

// Creation/Initialization
fn create(alloc: std.mem.Allocator, io: std.Io, config: Config) !*Self {
    const display = try wl.Display.connect(null);
    errdefer display.disconnect();

    const registry = try display.getRegistry();
    errdefer registry.destroy();

    const ctx = try alloc.create(Self);
    errdefer alloc.destroy(ctx);
    ctx.* = .{
        .shm = null,
        .compositor = null,
        .layer_shell = null,
        .display = display,
        .registry = registry,
        .outputs = try std.ArrayList(*Output).initCapacity(alloc, 5),
        .config = config,
        .alloc = alloc,
        .io = io,
    };

    return ctx;
}

pub fn init(alloc: std.mem.Allocator, io: std.Io, config: Config) !*Self {
    const ctx = try create(alloc, io, config);
    errdefer {
        ctx.deinit();
        alloc.destroy(ctx);
    }

    ctx.registry.setListener(*Self, registryListener, ctx);

    // Blocking roundtrip call to finish configure context
    if (ctx.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    if (ctx.discovery_error) |err| return err;
    if (ctx.shm == null) return error.NoWlShm;
    if (ctx.compositor == null) return error.NoWlCompositor;
    if (ctx.layer_shell == null) return error.NoLayerShell;

    // Bind outputs only after shared globals have been discovered, regardless
    // of their order in the registry. Hotplug uses the same addOutput path.
    for (ctx.pending_outputs.items) |name| {
        try ctx.addOutput(ctx.registry, name);
    }
    ctx.pending_outputs.clearRetainingCapacity();
    ctx.ready = true;
    return ctx;
}

/// Listen to output configuration events, collecting name, scale and initialize our output trackings
fn configureOutputListener(wl_output: *wl.Output, event: wl.Output.Event, self: *Self) void {
    const output = self.findOutput(wl_output) orelse {
        std.log.warn("Received unmanaged output", .{});
        return;
    };

    // Configure
    std.log.debug("Event {s} on output: {}", .{ @tagName(event), output.uname });
    switch (event) {
        .name => |name| {
            // Check if the output should be ignored
            if (isIgnored(name.name, self.config.ignored_outputs)) {
                self.removeOutput(output.uname);
            } else {
                output.setName(name.name) catch |err| {
                    std.log.warn("Failed to set name: {any}", .{err});
                };
            }
        },

        .scale => |scale| output.scale = scale.factor,

        .done => {
            self.restartOutput(output) catch {
                std.log.warn("Failed to configure output", .{});
                return;
            };
            std.log.info("Done configuring output {s}", .{
                output.name orelse "unnamed",
            });
        },

        else => {},
    }
}

/// Listen to the registry events, colllecting compositor connections and outputs
fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, self: *Self) void {
    // zig fmt: off
    switch (event) {
        .global => |global| {
            if (isInterface(global.interface, wl.Compositor)) {
                self.compositor = registry.bind(global.name, wl.Compositor, 6) catch return;

            } else if (isInterface(global.interface, wl.Shm)) {
                self.shm = registry.bind(global.name, wl.Shm, 1) catch return;

            } else if (isInterface(global.interface, zwlr.LayerShellV1)) {
                self.layer_shell = registry.bind(global.name, zwlr.LayerShellV1, 4) catch return;

            } else if (isInterface(global.interface, wl.Output)) {
                if (!self.ready) {
                    self.pending_outputs.append(self.alloc, global.name) catch |err| {
                        self.discovery_error = err;
                    };
                    return;
                }
                self.addOutput(registry, global.name) catch |err| {
                    std.log.err("Failed to register output: {}", .{err});
                };
            }
        },
        .global_remove => |global|{
            std.log.debug("Deregistering output: {}", .{global.name});
            self.removeOutput(global.name);
        },
    }
}

fn addOutput(
    self: *Self,
    registry: *wl.Registry,
    name: u32,
) !void {
    // Reserve the list entry before acquiring resources so registration cannot
    // fail after ownership has transferred to Output.
    try self.outputs.ensureUnusedCapacity(self.alloc, 1);
    const outputState = try self.alloc.create(Output);
    errdefer self.alloc.destroy(outputState);

    const output = try registry.bind(name, wl.Output, 4);
    errdefer output.release();
    outputState.* = try Output.init(
        self.alloc,
        self.io,
        output,
        name,
        self.shm.?,
        self.config.makeSnowSettings(),
    );
    self.outputs.appendAssumeCapacity(outputState);

    output.setListener(*Self, configureOutputListener, self);
}

/// Initializes required fields in OutputInfo to manage an output
fn restartOutput(self: *Self, output: *Output) !void {
    // Deactivate old if exists
    output.deactivate();
    try output.activate(self.compositor.?, self.layer_shell.?);

    output.snowSystem.resetFlakesTo(self.config.nFlakes);
}

fn removeOutput(self: *Self, name: u32) void {
    for (self.pending_outputs.items, 0..) |pending_name, i| {
        if (pending_name == name) {
            _ = self.pending_outputs.swapRemove(i);
            return;
        }
    }
    for (self.outputs.items, 0..) |state, i| {
        if (state.uname != name)
            continue;

        _ = self.outputs.swapRemove(i);

        state.deinit();
        self.alloc.destroy(state);
        return;
    }
}

pub fn deinit(self: *Self) void {
    for (self.outputs.items) |output| {
        output.deinit();
        self.alloc.destroy(output);
    }
    self.outputs.deinit(self.alloc);
    self.pending_outputs.deinit(self.alloc);
    if (self.layer_shell) |shell| shell.destroy();
    if (self.shm) |shm| shm.destroy();
    if (self.compositor) |compositor| compositor.destroy();
    self.registry.destroy();
    self.display.disconnect();
}
