const snow = @import("snow.zig");
const std = @import("std");

const Self = @This();

pub const Settings = struct {
    speed: f32 = 1.0,
    nFlakes: u32,
};

flakes: snow.FlakeArray,
prng: std.Random.DefaultPrng,
missing_flakes: u32,
alloc: std.mem.Allocator,
settings: Settings,

pub fn init(alloc: std.mem.Allocator, io: std.Io, settings: Settings) !Self {
    return .{
        .flakes = try snow.FlakeArray.initCapacity(alloc, settings.nFlakes),
        .missing_flakes = settings.nFlakes,
        .prng = std.Random.DefaultPrng.init(blk: {
            var seed: u64 = undefined;
            io.random(std.mem.asBytes(&seed));
            break :blk seed;
        }),
        .alloc = alloc,
        .settings = settings,
    };
}

pub fn resetFlakesTo(self: *Self, nFlakes: u32) void {
    for (self.flakes.items) |flake| {
        flake.deinit();
        self.alloc.destroy(flake);
    }

    self.flakes.clearRetainingCapacity();
    self.missing_flakes = nFlakes;
}

pub fn update(self: *Self, width: u32, height: u32, time_delta: u32) void {
    const scaled_delta = @as(f64, @floatFromInt(time_delta)) * self.settings.speed;
    const removed = snow.updateFlakes(&self.flakes, self.alloc, height, scaled_delta);
    self.missing_flakes = snow.spawnNewFlakes(
        self.prng.random(),
        &self.flakes,
        self.alloc,
        self.missing_flakes + removed,
        width,
    );
}

pub fn deinit(self: *Self) void {
    self.resetFlakesTo(0);
    self.flakes.deinit(self.alloc);
}

// Tests
fn checkParticleLifecycle(alloc: std.mem.Allocator) !void {
    var system = Self{
        .flakes = try snow.FlakeArray.initCapacity(alloc, 2),
        .prng = std.Random.DefaultPrng.init(42),
        .missing_flakes = 0,
        .alloc = alloc,
    };
    defer system.deinit();
    for (0..2) |_| {
        const flake = try snow.generateRandomFlake(system.prng.random(), 1920, alloc);
        system.flakes.appendAssumeCapacity(flake);
    }
    system.resetFlakesTo(10);
    try std.testing.expectEqual(@as(usize, 0), system.flakes.items.len);
    try std.testing.expectEqual(@as(u32, 10), system.missing_flakes);
    const flake = try snow.generateRandomFlake(system.prng.random(), 1920, alloc);
    system.flakes.appendAssumeCapacity(flake);
    // Expiration must free both the particle and its pattern allocations.
    _ = snow.updateFlakes(&system.flakes, alloc, 1, 1000);
    try std.testing.expectEqual(@as(usize, 0), system.flakes.items.len);
}

test "particle lifecycle cleans up on success and allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, checkParticleLifecycle, .{});
}
