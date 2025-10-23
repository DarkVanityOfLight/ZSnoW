const std = @import("std");
const flakes = @import("flakes/flake.zig");

pub const FlakeArray = std.ArrayList(*flakes.Flake);

fn clearBuffer(buffer_mem: []u32) void {
    @memset(buffer_mem, 0x00000000);
}

// Float flakes
pub fn generateRandomFlake(outputWidth: u32, alloc: std.mem.Allocator) !*flakes.Flake {
    var rand = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = 40315527606673217;
        _ = std.posix.getrandom(std.mem.asBytes(&seed)) catch break :blk seed;
        break :blk seed;
    });

    const flake_int = rand.random().uintAtMost(u8, flakes.FlakePatterns.len - 1);

    const pattern = flakes.FlakePatterns[flake_int];
    const flake = try alloc.create(flakes.Flake);

    const raw_exp = rand.random().floatExp(f64);
    const normalized_exp = std.math.clamp(raw_exp / 3.0, 0.0, 1.0); // Scale and normalize
    const dy = 0.1 + normalized_exp * (0.3 - 0.1); // Map to [0.1, 0.3]

    // zig fmt: off
    flake.* = try flakes.Flake.init(
        pattern,
        @floatFromInt(rand.random().uintAtMost(u32, outputWidth)),
        0,
        std.math.clamp(rand.random().int(u8), 0, 250),
        dy,
        0,
        rand.random().uintAtMost(usize, (pattern.maxScale orelse 1)),
        alloc
    );
    // zig fmt: on

    return flake;
}

pub fn updateFlakes(flakeArray: *FlakeArray, alloc: std.mem.Allocator, height: u32, timeDelta: u32) !u32 {
    const to_remove_raw = try alloc.alloc(u32, flakeArray.items.len);
    //std.debug.print("to_remove_raw {x}\n", .{@intFromPtr(to_remove_raw.ptr)});
    defer alloc.free(to_remove_raw);

    var i: u32 = 0;
    var j: u32 = 0;

    // Check that the timeDelta fits the float type
    const floatDelta: f64 = blk: {
        const trans: f64 = @floatFromInt(timeDelta);
        if (trans == std.math.inf(f64)) {
            break :blk @as(f64, 1);
        } else {
            break :blk trans;
        }
    };

    //FIXME: Check that the multiplication doesn't overflow

    for (flakeArray.items) |flake| {
        flake.move(flake.dx * floatDelta, flake.dy * floatDelta);
        if (flake.normalizeY() >= height) {
            to_remove_raw[i] = j;
            i += 1;
        }
        j += 1;
    }

    const to_remove = to_remove_raw[0..i];
    std.mem.sort(u32, to_remove, {}, comptime std.sort.desc(u32));
    for (to_remove) |index| {
        const flake = flakeArray.orderedRemove(index);
        flake.deinit();
        alloc.destroy(flake);
    }

    return i;
}

pub fn renderFlakes(flakeArray: *FlakeArray, buffer_mem: []u32, outputWidth: u32) !void {
    clearBuffer(buffer_mem);

    for (flakeArray.items) |flake| {
        renderFlakeToBuffer(flake, buffer_mem, outputWidth);
    }
}

pub fn spawnNewFlakes(flakeArray: *FlakeArray, alloc: std.mem.Allocator, i: u32, outputWidth: u32) !u32 {
    var rand = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        _ = std.posix.getrandom(std.mem.asBytes(&seed)) catch null;
        break :blk seed;
    });

    var j = i;
    for (0..i) |_| {
        if (rand.random().uintAtMost(u16, 1000) >= 999) {
            const flake = try generateRandomFlake(outputWidth, alloc);
            try flakeArray.append(alloc, flake);
            j -= 1;
        }
    }

    return j;
}

fn zToColor(z: u8) u32 {
    const bigZ: u16 = @intCast(z);
    const alpha: u32 = std.math.clamp(std.math.clamp(255 - z, 50, 255) + bigZ, 0, 255);
    const gray_factor: u32 = std.math.clamp(std.math.clamp(255 - z, 100, 255) + bigZ, 0, 255);

    const red = gray_factor;
    const green = gray_factor;
    const blue = gray_factor;

    return (alpha << 24) | (red << 16) | (green << 8) | blue;
}

fn renderFlakeToBuffer(flake: *const flakes.Flake, m: []u32, width: u32) void {
    var row_num: u32 = 0;

    const color = zToColor(flake.z);
    const coordinate = flake.normalizeCoordinates();

    for (flake.pattern.pattern) |row| {
        var column_num: u32 = 0; // Reset column_num at the beginning of each row
        for (row) |pv| {
            if (pv) {
                // Calculate the index in the buffer and ensure we are within bounds
                const index = ((coordinate.y + row_num) * width) + (coordinate.x + column_num);
                if (index < m.len) {
                    //Shift alpha chanel to its position and OR it with color white
                    m[index] = color;
                }
            }
            column_num += 1;
        }
        row_num += 1;
    }
}
