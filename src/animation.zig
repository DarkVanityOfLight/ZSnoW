const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const snow = @import("snow.zig");
const OutputState = @import("OutputState.zig");

const std = @import("std");

pub fn requestFrame(output: *OutputState) !void {
    const state = &output.activeState.?;
    if (state.frame_callback != null) return;

    const cb = try state.surface.frame();
    cb.setListener(*OutputState, frameCallback, output);
    state.frame_callback = cb;
}

fn frameCallback(cb: *wl.Callback, event: wl.Callback.Event, output: *OutputState) void {
    if (!output.info.running) return;

    if (output.activeState) |*s| {
        // Handle future callbacks
        s.frame_callback = null;
        cb.destroy();

        // Calculate time between callbacks
        const currentTimeInMs = event.done.callback_data;
        const timeDelta = currentTimeInMs -% (output.info.time);
        output.info.time = currentTimeInMs;

        output.snowSystem.update(output.info.width, output.info.height, timeDelta);

        // Work on the next frame if buffer is free
        if (s.doubleBuffer.?.swap())
            snow.renderFlakes(
                &output.snowSystem.flakes,
                s.doubleBuffer.?.mem(),
                output.info.width,
            ) catch return;

        output.attachCurrentBuffer();
        s.surface.damage(0, 0, @intCast(output.info.width), @intCast(output.info.height));

        requestFrame(output) catch |err| {
            std.log.err("Cannot schedule animation frame: {s}", .{@errorName(err)});
            output.info.running = false;
            return;
        };

        s.surface.commit();
    } else std.log.warn("Trying to render unitialized output", .{});
}
