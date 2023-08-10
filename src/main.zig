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

    std.debug.print("title: {s}\n", .{args.title});
    std.debug.print("target remote: {?s}\n", .{args.target_remote});
    std.debug.print("source remote: {?s}\n", .{args.source_remote});
    std.debug.print("target branch: {?s}\n", .{args.target_branch});
    std.debug.print("source branch: {?s}\n", .{args.source_branch});
}
