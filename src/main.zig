const std = @import("std");
const clapz = @import("clapz");
const repository = @import("repo.zig");

const Args = struct {
    title: []const u8,
    target_remote: ?[]const u8,
    source_remote: ?[]const u8,
    target_branch: ?[]const u8,
    source_branch: ?[]const u8,
};

const Parser = clapz.Parser(Args, .{
    .name = "git-pr",
    .author = "eulegang",
    .version = "0.1.0",
    .desc = "create a pull request",
}, .{
    .title = .{
        .short = 't',
        .long = "title",
        .doc = "title of the pullrequest",
    },

    .target_remote = .{
        .short = 'r',
        .long = "remote",
        .doc = "target remote",
    },

    .source_remote = .{
        .short = 'R',
        .long = "source-remote",
        .doc = "source remote",
    },

    .target_branch = .{
        .short = 'b',
        .long = "branch",
        .doc = "target branch",
    },

    .source_branch = .{
        .short = 'B',
        .long = "source-branch",
        .doc = "source branch",
    },
});

pub fn main() !void {
    var arg_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arg_alloc.deinit();

    var parser = try Parser.init(arg_alloc.allocator());
    defer parser.deinit();

    var args = try parser.parse_args();

    var repo = try repository.Repo.open();
    defer repo.deinit();

    var config = try repo.config();
    defer config.deinit();

    var buf: [4096]u8 = undefined;

    if (args.target_remote) |dst| {
        @memcpy(buf[0..dst.len], dst);
        buf[dst.len] = 0;
        var remote_name: [*]const u8 = &buf;
        var remote = try repo.remote(remote_name);
        defer remote.deinit();
        std.debug.print("dst remote url: {s}\n", .{remote.url()});
    }

    if (try config.var_string("user.name", arg_alloc.allocator())) |username| {
        std.debug.print("username: {s}\n", .{username});
    }
}
