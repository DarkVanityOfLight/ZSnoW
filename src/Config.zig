const std = @import("std");

const zli = @import("zli");
const CommandContext = @import("zli").CommandContext;
const SnowSettings = @import("SnowSystem.zig").Settings;

const ExecFn = *const fn (ctx: CommandContext) anyerror!void;

const Self = @This();

ignored_outputs: std.mem.TokenIterator(u8, .scalar),
speed_multiplier: f32,
nFlakes: usize = 200,
scale: usize = 1,

pub fn parseCli(ctx: CommandContext) !Self {
    const s = ctx.flag("ignore", []const u8);
    const outputs = std.mem.tokenizeScalar(u8, s, ',');

    const speed_multiplier_s = ctx.flag("speed", []const u8);
    const speed_multiplier = try std.fmt.parseFloat(f32, speed_multiplier_s);

    const nFlakes = ctx.flag("nFlakes", usize);

    const scale = ctx.flag("scale", usize);

    return .{
        .ignored_outputs = outputs,
        .speed_multiplier = speed_multiplier,
        .nFlakes = nFlakes,
        .scale = scale,
    };
}

pub fn cliSetup(io: std.Io, gpa: std.mem.Allocator, execFn: ExecFn) !*zli.Command {
    var wbuf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.Writer.init(.stdout(), io, &wbuf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var rbuf: [1024]u8 = undefined;
    var stdin_reader = std.Io.File.Reader.init(.stdin(), io, &rbuf);
    const stdin = &stdin_reader.interface;

    const init_options = zli.InitOptions{
        .allocator = gpa,
        .io = io,
        .writer = stdout,
        .reader = stdin,
    };

    const root = try zli.Command.init(
        init_options,
        .{
            .name = "ZsnoW",
            .description = "Xsnow on Wayland",
            .version = .{ .major = 0, .minor = 1, .patch = 0, .pre = null, .build = null },
        },
        execFn,
    );

    try root.addFlag(.{
        .name = "ignore",
        .description = "Ignore an output, comma separated values OUT-1,OUT-2 ...",
        .type = .String,
        .default_value = .{ .String = "" },
    });

    try root.addFlag(.{
        .name = "speed",
        .description = "Particle speed multiplier as float",
        .type = .String,
        .default_value = .{ .String = "1.0" },
    });

    try root.addFlag(.{
        .name = "nFlakes",
        .description = "Set the number of flakes simulated at the same time at most",
        .type = .Int,
        .default_value = .{ .Int = 200 },
    });

    try root.addFlag(.{
        .name = "scale",
        .description = "Flake size multiplier",
        .type = .Int,
        .default_value = .{ .Int = 1 },
    });

    try root.addCommands(&.{});
    return root;
}

pub fn makeSnowSettings(self: *Self) SnowSettings {
    return .{
        .speed = self.speed_multiplier,
        .nFlakes = self.nFlakes,
        .scale = self.scale,
    };
}
