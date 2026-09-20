const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const posix = std.posix;

const Self = @This();

buffers: [2]*wl.Buffer,
memory: []align(4096) u8,
pixels: [2][]u32,
current_index: usize = 0,
busy: [2]bool = .{ false, false },

pub fn init(io: std.Io, width: usize, height: usize, name: []const u8, shm: *wl.Shm) !Self {
    const stride = try std.math.mul(usize, width, @sizeOf(u32));
    const buffer_size = try std.math.mul(usize, stride, height);
    const total_size = try std.math.mul(usize, buffer_size, 2);

    const fd = try posix.memfd_create(name, 0);

    const file: std.Io.File = .{
        .handle = fd,
        .flags = .{ .nonblocking = false },
    };
    defer file.close(io);

    try file.setLength(io, total_size);

    // Map into memory
    const memory = try posix.mmap(
        null,
        total_size,
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .SHARED },
        fd,
        0,
    );
    errdefer posix.munmap(memory);

    @memset(memory, 0);

    // Tell wayland
    const pool = try shm.createPool(fd, @intCast(total_size));
    defer pool.destroy();

    const buffer1 = try pool.createBuffer(0, @intCast(width), @intCast(height), @intCast(stride), .argb8888);
    errdefer buffer1.destroy();
    const buffer2 = try pool.createBuffer(@intCast(buffer_size), @intCast(width), @intCast(height), @intCast(stride), .argb8888);
    errdefer buffer2.destroy();

    const all_pixels = std.mem.bytesAsSlice(u32, memory);
    const pixels_per_buffer = all_pixels.len / 2;

    return .{
        .buffers = .{ buffer1, buffer2 },
        .memory = memory,
        .pixels = .{
            all_pixels[0..pixels_per_buffer],
            all_pixels[pixels_per_buffer..],
        },
    };
}

pub fn current(self: *Self) *wl.Buffer {
    return self.buffers[self.current_index];
}

pub fn swap(self: *Self) bool {
    const next = self.current_index ^ 1;

    if (self.busy[next])
        return false;

    self.current_index = next;
    return true;
}

pub fn mem(self: *Self) []u32 {
    return self.pixels[self.current_index];
}

pub fn deinit(self: *Self) void {
    for (self.buffers) |buffer| buffer.destroy();

    posix.munmap(self.memory);
}

pub fn listen(self: *Self) void {
    for (self.buffers) |buffer| {
        buffer.setListener(*Self, bufferListener, self);
    }
}

fn bufferListener(
    buffer: *wl.Buffer,
    event: wl.Buffer.Event,
    self: *Self,
) void {
    switch (event) {
        .release => {
            for (self.buffers, 0..) |b, i| {
                if (b == buffer) {
                    self.busy[i] = false;
                    return;
                }
            }
        },
    }
}

pub fn attach(self: *Self, surface: *wl.Surface) void {
    const i = self.current_index;

    surface.attach(self.buffers[i], 0, 0);
    self.busy[i] = true;
}
