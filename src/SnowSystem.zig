const snow = @import("snow.zig");
const std = @import("std");

const Self = @This();

flakes: snow.FlakeArray,
prng: std.Random.DefaultPrng,
missing_flakes: u32,
alloc: std.mem.Allocator,

pub fn init(alloc: std.mem.Allocator, io: std.Io, nFlakes: u32) !Self {
    return .{
        .flakes = try snow.FlakeArray.initCapacity(alloc, nFlakes),
        .missing_flakes = nFlakes,
        .prng = std.Random.DefaultPrng.init(blk: {
            var seed: u64 = undefined;
            io.random(std.mem.asBytes(&seed));
            break :blk seed;
        }),
        .alloc = alloc,
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

pub fn deinit(self: *Self) void {
    for (self.flakes.items) |flake| {
        flake.deinit();
        self.alloc.destroy(flake);
    }

    self.flakes.deinit(self.alloc);
}
