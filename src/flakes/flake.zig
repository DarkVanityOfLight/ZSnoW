const std = @import("std");

pub const Coordinates = struct { x: usize, y: usize };

// zig fmt: off
pub const FlakePattern = struct {
    x_size: u16,
    y_size: u16,
    pattern: []const []const bool,
    maxScale: ?usize, // Should this pattern be scaled and if yes how much
};



pub const flake0 = FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ true, false, true },
    &[_]bool{ false, true, false },
    &[_]bool{ true, false, true },
}, .y_size = 3, .x_size = 3, .maxScale = 3 };

pub const flake1 = FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ false, true, false, false, false, true, false, false },
    &[_]bool{ true, true, false, true, false, true, true, false },
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ false, true, false, true, false, true, false, false },
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ true, true, false, true, false, true, true, false },
    &[_]bool{ false, true, false, false, false, true, false, false },
    &[_]bool{ false, false, false, false, false, false, false, false },
}, .y_size = 8, .x_size = 8, .maxScale = 1 };

pub const flake2 = FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ true, true, false, false, false, false, false, false, false, false, false, false, false, true, true, false },
    &[_]bool{ false, true, true, false, false, false, false, false, false, false, false, false, true, true, false, false },
    &[_]bool{ false, false, true, true, false, false, false, false, false, false, false, true, true, false, false, false },
    &[_]bool{ false, false, false, true, true, false, false, false, false, false, true, true, false, false, false, false },
    &[_]bool{ false, false, false, false, true, true, false, false, false, true, true, false, false, false, false, false },
    &[_]bool{ false, false, false, false, false, true, true, false, true, true, false, false, false, false, false, false },
    &[_]bool{ false, false, false, false, false, false, true, true, true, false, false, false, false, false, false, false },
    &[_]bool{ false, false, false, false, false, true, true, false, true, true, false, false, false, false, false, false },
    &[_]bool{ false, false, false, false, true, true, false, false, false, true, true, false, false, false, false, false },
    &[_]bool{ false, false, false, true, true, false, false, false, false, false, true, true, false, false, false, false },
    &[_]bool{ false, false, true, true, false, false, false, false, false, false, false, true, true, false, false, false },
    &[_]bool{ false, true, true, false, false, false, false, false, false, false, false, false, true, true, false, false },
    &[_]bool{ true, true, false, false, false, false, false, false, false, false, false, false, false, true, true, false },
}, .y_size = 13, .x_size = 16, .maxScale = 1 };

pub const flake3 = FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ false, false, false, true, false, false, false, false },
    &[_]bool{ true, false, false, true, false, false, true, false },
    &[_]bool{ false, true, true, false, true, true, false, false },
    &[_]bool{ true, false, false, true, false, false, true, false },
    &[_]bool{ false, false, false, true, false, false, false, false },
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ false, false, false, false, false, false, false, false },
}, .y_size = 8, .x_size = 8, .maxScale = 1 };

pub const flake4 =
    FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ false, true, false, false, false, true, false, false },
    &[_]bool{ true, true, false, true, false, true, true, false },
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ false, true, false, true, false, true, false, false },
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ true, true, false, true, false, true, true, false },
    &[_]bool{ false, true, false, false, false, true, false, false },
    &[_]bool{ false, false, false, false, false, false, false, false },
}, .y_size = 8, .x_size = 8, .maxScale = 1 };

pub const flake5 =
    FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ false, false, false, true, false, false, false, false },
    &[_]bool{ true, false, false, true, false, false, true, false },
    &[_]bool{ false, true, true, false, true, true, false, false },
    &[_]bool{ true, false, false, true, false, false, true, false },
    &[_]bool{ false, false, false, true, false, false, false, false },
    &[_]bool{ false, false, true, false, true, false, false, false },
    &[_]bool{ false, false, false, false, false, false, false, false },
}, .y_size = 8, .x_size = 8, .maxScale = 1 };

pub const flake6 = FlakePattern{ .pattern = &[_][]const bool{
    &[_]bool{ true, false, true },
    &[_]bool{ false, true, false },
    &[_]bool{ true, false, true },
}, .y_size = 3, .x_size = 3, .maxScale = 2 };

// ============= Minecraft Flakes =============
pub const mcFlake0 = FlakePattern{
    .pattern = &[_][]const bool{
        &[_]bool{ false, true,  false},
        &[_]bool{ true,  false, true },
        &[_]bool{ false, true,  false }
    }, .y_size = 3, .x_size = 3, .maxScale = 3
};


pub const mcFlake1 = FlakePattern{
    .pattern = &[_][]const bool{
        &[_]bool{ false, true, false },
        &[_]bool{ true, true, true },
        &[_]bool{ false, true, false}
    }, .y_size = 3, .x_size = 3, .maxScale = 3
};

pub const mcFlake2 = FlakePattern{
    .pattern = &[_][]const bool{
        &[_]bool{true},
    }, .y_size = 1, .x_size = 1, .maxScale = 4
};

// zig fmt: on
pub const Flake = struct {
    pattern: *const FlakePattern,
    x: f64,
    y: f64,
    z: u8,
    dy: f64,
    dx: f64,
    scale: usize,
    arena: std.heap.ArenaAllocator,

    pub fn init(pattern: *const FlakePattern, x: f32, y: f32, z: u8, dy: f64, dx: f64, scale: ?usize, alloc: std.mem.Allocator) !Flake {
        var arena = std.heap.ArenaAllocator.init(alloc);
        errdefer arena.deinit();
        const arenaAlloc = arena.allocator();
        const scaledPattern = try arenaAlloc.create(FlakePattern);
        if ((scale orelse 0) > 1) {
            scaledPattern.* = try scalePattern(
                pattern.*,
                scale.?,
                scale.?,
                arenaAlloc,
            );
        } else {
            scaledPattern.* = pattern.*;
        }

        // zig fmt: off
        return Flake{ 
            .pattern = scaledPattern,
            .x = x,
            .y = y,
            .z = z,
            .dy = dy,
            .dx = dx,
            .scale = (scale orelse 1),
            .arena = arena
        };
        // zig fmt: on
    }

    // dx, dy to move
    // FIXME: Check that we don't overflow
    pub fn move(flake: *Flake, dx: f64, dy: f64) void {
        flake.x = flake.x + dx;
        flake.y = flake.y + dy;
    }

    pub fn normalizeCoordinates(flake: *const Flake) Coordinates {
        const x: usize = @intFromFloat(flake.x);
        const y: usize = @intFromFloat(flake.y);
        return Coordinates{ .x = x, .y = y };
    }

    pub fn normalizeX(flake: *const Flake) usize {
        return @intFromFloat(flake.x);
    }

    pub fn normalizeY(flake: *const Flake) usize {
        return @intFromFloat(flake.y);
    }

    pub fn deinit(flake: *const Flake) void {
        flake.arena.deinit();
    }
};

// pub const FlakePatterns = [_]*const FlakePattern{ &flake0, &flake1, &flake3, &flake4, &flake5, &flake6 };
// pub const FlakePatterns = [_]*const FlakePattern{ &mcFlake0, &mcFlake1, &mcFlake2, &mcFlake3 };

pub const FlakePatterns = [_]*const FlakePattern{ &mcFlake0, &mcFlake1, &mcFlake2, &flake0, &flake1, &flake3, &flake4, &flake5, &flake6 };

// TODO implement a xpm parser
// TODO Scale flakes

pub fn scalePattern(flakePattern: FlakePattern, scaleX: usize, scaleY: usize, alloc: std.mem.Allocator) !FlakePattern {
    const xSize = flakePattern.x_size * scaleX;
    const ySize = flakePattern.y_size * scaleY;

    // Allocate the new pattern (ySize x xSize)
    const newPattern = try alloc.alloc([]bool, ySize);
    errdefer alloc.free(newPattern);
    var initialized: usize = 0;
    errdefer for (newPattern[0..initialized]) |row| alloc.free(row);
    for (0..ySize) |i| {
        newPattern[i] = try alloc.alloc(bool, xSize);
        initialized += 1;
    }

    // Fill the new pattern with scaled values
    for (0..ySize) |row| {
        for (0..xSize) |column| {
            // Find the corresponding source coordinates
            const srcY = (row * flakePattern.y_size) / ySize;
            const srcX = (column * flakePattern.x_size) / xSize;

            // Set the pixel in the new pattern to match the original
            newPattern[row][column] = flakePattern.pattern[srcY][srcX];
        }
    }

    // Return the scaled pattern
    return FlakePattern{
        .y_size = @intCast(ySize),
        .x_size = @intCast(xSize),
        .pattern = newPattern,
        .maxScale = null, // indicate this shouldn't be scaled further
    };
}

pub fn printPattern(flake: FlakePattern) void {
    for (flake.pattern) |row| {
        for (row) |value| {
            std.debug.print("{}", .{@intFromBool(value)});
        }
        std.debug.print("\n", .{});
    }
}

test "test scaling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    const scaledPattern = try scalePattern(flake0, 2, 2, allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(u16, 6), scaledPattern.x_size);
    try std.testing.expectEqual(@as(u16, 6), scaledPattern.y_size);
    for (scaledPattern.pattern, 0..) |row, y| {
        for (row, 0..) |pixel, x| {
            try std.testing.expectEqual(flake0.pattern[y / 2][x / 2], pixel);
        }
    }
}

fn checkScalingAllocations(alloc: std.mem.Allocator) !void {
    const pattern = try scalePattern(flake0, 3, 2, alloc);
    defer alloc.free(pattern.pattern);
    defer for (pattern.pattern) |row| alloc.free(row);
    try std.testing.expectEqual(@as(u16, 9), pattern.x_size);
    try std.testing.expectEqual(@as(u16, 6), pattern.y_size);
}

test "scaling cleans up partial allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, checkScalingAllocations, .{});
}

fn checkFlakeAllocations(alloc: std.mem.Allocator) !void {
    const flake = try Flake.init(&flake0, 0, 0, 0, 0.1, 0, 3, alloc);
    defer flake.deinit();
}

test "flake initialization cleans up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, checkFlakeAllocations, .{});
}
