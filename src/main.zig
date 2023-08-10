const std = @import("std");
const clapz = @import("clapz");

const Args = struct {
    title: []const u8,
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
});

pub fn main() !void {
    var arg_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arg_alloc.deinit();

    var parser = try Parser.init(arg_alloc.allocator());
    defer parser.deinit();

    var args = try parser.parse_args();

    std.debug.print("title: {s}\n", .{args.title});
}
