const std = @import("std");
const flakes = @import("flakes/flake.zig");

pub const FlakeArray = std.ArrayList(*flakes.Flake);

fn clearBuffer(buffer_mem: []u32) void {
    @memset(buffer_mem, 0x00000000);
}

// Float flakes
pub fn generateRandomFlake(rand: std.Random, outputWidth: u32, alloc: std.mem.Allocator) !*flakes.Flake {
    const flake_int = rand.uintAtMost(u8, flakes.FlakePatterns.len - 1);

    const pattern = flakes.FlakePatterns[flake_int];
    const flake = try alloc.create(flakes.Flake);

    const raw_exp = rand.floatExp(f64);
    const normalized_exp = std.math.clamp(raw_exp / 3.0, 0.0, 1.0); // Scale and normalize
    const dy = 0.1 + normalized_exp * (0.3 - 0.1); // Map to [0.1, 0.3]

    flake.* = try flakes.Flake.init(
        pattern,
        @floatFromInt(rand.uintAtMost(u32, outputWidth)),
        0,
        std.math.clamp(rand.int(u8), 0, 250),
        dy,
        0,
        rand.uintAtMost(usize, (pattern.maxScale orelse 1)),
        alloc,
    );

    return flake;
}

pub fn updateFlakes(flakeArray: *FlakeArray, alloc: std.mem.Allocator, height: u32, timeDelta: u32) u32 {
    const floatDelta = @as(f32, @floatFromInt(timeDelta));
    var removed: u32 = 0;
    var i: usize = flakeArray.items.len;

    while (i > 0) {
        i -= 1;
        const flake = flakeArray.items[i];

        flake.move(flake.dx * floatDelta, flake.dy * floatDelta);

        if (flake.normalizeY() >= height) {
            _ = flakeArray.swapRemove(i);
            flake.deinit();
            alloc.destroy(flake);
            removed += 1;
        }
    }

    return removed;
}

pub fn renderFlakes(flakeArray: *FlakeArray, buffer_mem: []u32, outputWidth: u32) !void {
    clearBuffer(buffer_mem);

    for (flakeArray.items) |flake| {
        renderFlakeToBuffer(flake, buffer_mem, outputWidth);
    }
}

pub fn spawnNewFlakes(rand: std.Random, flakeArray: *FlakeArray, alloc: std.mem.Allocator, i: u32, outputWidth: u32) !u32 {
    var j = i;
    for (0..i) |_| {
        if (rand.uintAtMost(u16, 1000) >= 999) {
            const flake = try generateRandomFlake(rand, outputWidth, alloc);
            try flakeArray.append(alloc, flake);
            j -= 1;
        }
    }

    return j;
}

fn zToColor(z: u8) u32 {
    // Bias: Dividing z prevents the values from ever reaching 0 (black/transparent).
    // Alpha will range from 255 down to 128 (z / 2)
    // RGB will range from 255 down to 192 (z / 4)
    const alpha: u32 = 255 - (@as(u32, z) / 2);
    const gray: u32 = 255 - (@as(u32, z) / 4);

    const premul = (gray * alpha) / 255;

    return (alpha << 24) | (premul << 16) | (premul << 8) | premul;
}

fn renderFlakeToBuffer(flake: *const flakes.Flake, m: []u32, width: u32) void {
    const color = zToColor(flake.z);
    const coordinate = flake.normalizeCoordinates();
    const height: u32 = @intCast(m.len / width);

    for (flake.pattern.pattern, 0..) |row, row_num| {
        for (row, 0..) |pv, column_num| {
            if (!pv) continue;

            const x = coordinate.x + column_num;
            const y = coordinate.y + row_num;

            if (x >= width or y >= height) continue;

            // Calculate the index in the buffer and ensure we are within bounds
            const index = y * width + x;
            m[index] = color;
        }
    }
}
