//const github = @import("github.zig");

pub const PullRequest = struct {
    title: []const u8,
    description: []const u8,
    source: Coord,
    target: Coord,
};

pub const Coord = struct {
    repo: []const u8,
    branch: []const u8,
};
