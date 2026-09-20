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
    errdefer alloc.destroy(flake);

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

pub fn renderFlakes(flakeArray: *FlakeArray, buffer_mem: []u32, buffer_width: u32, scale: u32) !void {
    clearBuffer(buffer_mem);

    for (flakeArray.items) |flake| {
        renderFlakeToBuffer(flake, buffer_mem, buffer_width, scale);
    }
}

pub fn spawnNewFlakes(rand: std.Random, flakeArray: *FlakeArray, alloc: std.mem.Allocator, i: u32, outputWidth: u32) u32 {
    var j = i;
    for (0..i) |_| {
        if (rand.uintAtMost(u16, 1000) >= 999) {
            const flake = generateRandomFlake(rand, outputWidth, alloc) catch continue;
            flakeArray.append(alloc, flake) catch {
                flake.deinit();
                alloc.destroy(flake);
                continue;
            };
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

// Simulation coordinates and pattern cells are logical units; width is in pixels.
fn renderFlakeToBuffer(flake: *const flakes.Flake, m: []u32, width: u32, scale: u32) void {
    std.debug.assert(scale > 0);
    if (width == 0) return;
    const color = zToColor(flake.z);
    const coordinate = flake.normalizeCoordinates();
    const height = m.len / width;

    for (flake.pattern.pattern, 0..) |row, row_num| {
        for (row, 0..) |pv, column_num| {
            if (!pv) continue;

            const logical_x = @as(usize, coordinate.x) + column_num;
            const logical_y = @as(usize, coordinate.y) + row_num;
            if (logical_x >= width / scale or logical_y >= height / scale) continue;

            const x = logical_x * scale;
            const y = logical_y * scale;
            for (0..scale) |dy| {
                const start = (y + dy) * width + x;
                @memset(m[start..][0..scale], color);
            }
        }
    }
}

test "rendering scales positions and patterns and clips at logical edges" {
    var flake = try flakes.Flake.init(&flakes.flake0, 2, 1, 0, 0, 0, 1, std.testing.allocator);
    defer flake.deinit();
    var items = [_]*flakes.Flake{&flake};
    var array: FlakeArray = .{ .items = &items, .capacity = items.len };

    // A 4x3 logical surface clips the right and bottom of this 3x3 pattern.
    const expected = [_]u32{
        0, 0, 0,          0,
        0, 0, 0xffffffff, 0,
        0, 0, 0,          0xffffffff,
    };
    for ([_]u32{ 1, 2, 3 }) |scale| {
        const width = 4 * scale;
        const pixels = try std.testing.allocator.alloc(u32, width * 3 * scale);
        defer std.testing.allocator.free(pixels);
        @memset(pixels, 0x12345678);
        try renderFlakes(&array, pixels, width, scale);
        for (pixels, 0..) |pixel, i| {
            const logical_x = (i % width) / scale;
            const logical_y = (i / width) / scale;
            try std.testing.expectEqual(expected[logical_y * 4 + logical_x], pixel);
        }
    }
}
