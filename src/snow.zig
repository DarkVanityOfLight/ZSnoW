const std = @import("std");
const flakes = @import("flakes/flake.zig");

pub const FlakeArray = std.ArrayList(*flakes.Flake);

fn clearBuffer(buffer_mem: []u32) void {
    @memset(buffer_mem, 0x00000000);
}

// Float flakes
pub fn generateRandomFlake(rand: std.Random, outputWidth: usize, scale: usize, alloc: std.mem.Allocator) !*flakes.Flake {
    const flake_int = rand.uintAtMost(u8, flakes.FlakePatterns.len - 1);

    const pattern = flakes.FlakePatterns[flake_int];
    const flake = try alloc.create(flakes.Flake);
    errdefer alloc.destroy(flake);

    const raw_exp = rand.floatExp(f64);
    const normalized_exp = std.math.clamp(raw_exp / 3.0, 0.0, 1.0); // Scale and normalize
    const dy = 0.1 + normalized_exp * (0.3 - 0.1); // Map to [0.1, 0.3]

    const random_scale = @max(
        rand.uintAtMost(usize, pattern.maxScale orelse 1),
        1,
    );
    const final_scale = random_scale * scale;

    flake.* = try flakes.Flake.init(
        pattern,
        @floatFromInt(rand.uintAtMost(usize, outputWidth)),
        0,
        std.math.clamp(rand.int(u8), 0, 250),
        dy,
        0,
        final_scale,
        alloc,
    );

    return flake;
}

pub fn updateFlakes(flakeArray: *FlakeArray, alloc: std.mem.Allocator, height: usize, timeDelta: f64) usize {
    var removed: usize = 0;
    var i: usize = flakeArray.items.len;

    while (i > 0) {
        i -= 1;
        const flake = flakeArray.items[i];

        flake.move(flake.dx * timeDelta, flake.dy * timeDelta);

        if (flake.normalizeY() >= height) {
            _ = flakeArray.swapRemove(i);
            flake.deinit();
            alloc.destroy(flake);
            removed += 1;
        }
    }

    return removed;
}

pub fn renderFlakes(flakeArray: *FlakeArray, buffer_mem: []u32, buffer_width: usize, scale: usize, color: u32) !void {
    clearBuffer(buffer_mem);

    for (flakeArray.items) |flake| {
        renderFlakeToBuffer(flake, buffer_mem, buffer_width, scale, color);
    }
}

pub fn spawnNewFlakes(
    rand: std.Random,
    flakeArray: *FlakeArray,
    alloc: std.mem.Allocator,
    i: usize,
    outputWidth: usize,
    scale: usize,
) usize {
    var j = i;
    for (0..i) |_| {
        if (rand.uintAtMost(u16, 1000) >= 999) {
            const flake = generateRandomFlake(rand, outputWidth, scale, alloc) catch continue;
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

fn taintZ(color: u32, z: u8) u32 {
    const alpha: u32 = 255 - @as(u32, z) / 2;
    const shade: u32 = 255 - @as(u32, z) / 4;

    const r = (color >> 16) & 0xff;
    const g = (color >> 8) & 0xff;
    const b = color & 0xff;

    // Shade, then premultiply by alpha.
    const pr = (r * shade / 255) * alpha / 255;
    const pg = (g * shade / 255) * alpha / 255;
    const pb = (b * shade / 255) * alpha / 255;

    return (alpha << 24) | (pr << 16) | (pg << 8) | pb;
}

// Simulation coordinates and pattern cells are logical units; width is in pixels.
fn renderFlakeToBuffer(flake: *const flakes.Flake, m: []u32, width: usize, scale: usize, color: u32) void {
    std.debug.assert(scale > 0);
    if (width == 0) return;
    const tainted_color = taintZ(color, flake.z);
    const coordinate = flake.normalizeCoordinates();
    const height = m.len / width;

    for (flake.pattern.pattern, 0..) |row, row_num| {
        for (row, 0..) |pv, column_num| {
            if (!pv) continue;

            const logical_x = coordinate.x + column_num;
            const logical_y = coordinate.y + row_num;
            if (logical_x >= width / scale or logical_y >= height / scale) continue;

            const x = logical_x * scale;
            const y = logical_y * scale;
            for (0..scale) |dy| {
                const start = (y + dy) * width + x;
                @memset(m[start..][0..scale], tainted_color);
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
    for ([_]usize{ 1, 2, 3 }) |scale| {
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
