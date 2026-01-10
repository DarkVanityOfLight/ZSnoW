const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const posix = std.posix;

const Self = @This();

buffer1: *wl.Buffer,
buffer2: *wl.Buffer,
i: bool,
memory1: []u32,
memory2: []u32,
fd: i32,
total_size: u64,
alloc: std.mem.Allocator,

// FIXME: Check that width height are valid
pub fn init(alloc: std.mem.Allocator, width: u32, height: u32, name: []const u8, shm: *wl.Shm) !Self {
    // std.debug.print("{}x{}\n", .{ width, height });
    const stride: u64 = width * 4;
    const size = stride * height * 2;
    const fd = try posix.memfd_create(name, 0);
    try posix.ftruncate(fd, size);

    const data = blk: {
        const raw = try posix.mmap(
            null,
            @intCast(size),
            posix.PROT.READ | posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            fd,
            0,
        );
        break :blk std.mem.bytesAsSlice(u32, raw);
    };

    const pool = try shm.createPool(fd, @intCast(size));

    const buffer1 = try pool.createBuffer(
        0,
        @intCast(width),
        @intCast(height),
        @intCast(stride),
        wl.Shm.Format.argb8888,
    );
    const buffer2 = try pool.createBuffer(
        @intCast(size / 2),
        @intCast(width),
        @intCast(height),
        @intCast(stride),
        wl.Shm.Format.argb8888,
    );
    pool.destroy();

    const db = Self{
        .buffer1 = buffer1,
        .buffer2 = buffer2,
        .memory1 = data[0..(size / (2 * 4))],
        .memory2 = data[(size / (2 * 4)) .. size / 4],
        .i = true,
        .fd = fd,
        .total_size = size,
        .alloc = alloc,
    };
    return db;
}

pub fn current(self: *Self) *wl.Buffer {
    return if (self.i) self.buffer1 else self.buffer2;
}

pub fn swap(self: *Self) void {
    self.i = !self.i;
}

pub fn mem(self: *Self) []u32 {
    return if (self.i) self.memory1 else self.memory2;
}

pub fn deinit(self: *Self) void {
    self.buffer1.destroy();
    self.buffer2.destroy();
    // TODO: Is this required?
    const memory: []const u32 = self.memory1.ptr[0 .. self.memory1.len + self.memory2.len];
    const u8mem: []align(4096) const u8 = @alignCast(std.mem.bytesAsSlice(u8, memory));

    std.posix.munmap(u8mem);
    posix.close(self.fd);
}
