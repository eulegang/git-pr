const std = @import("std");
const clapz = @import("clapz");
const credsys = @import("credsys");

const repository = @import("repo.zig");
const pr = @import("pr/mod.zig");
const Freader = @import("freader.zig").Freader;

const Args = struct {
    title: []const u8,
    description: ?[]const u8,
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
        .doc = "title of the pull request",
    },

    .description = .{
        .short = 'd',
        .long = "description",
        .doc = "description of pull request",
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

pub const Error = error{
    MalconfiguredSource,
    MalconfiguredTarget,
};

pub fn main() !void {
    var arg_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arg_alloc.deinit();

    var parser = try Parser.init(arg_alloc.allocator());
    defer parser.deinit();

    var args = try parser.parse_args();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var alloc = gpa.allocator();

    var repo = try repository.Repo.open();
    defer repo.deinit();

    var config = try repo.config();
    defer config.deinit();

    var pull_request = try build_pr(args, &repo, &config, alloc);
    defer destroy_pr(pull_request, alloc);

    var credentials = credsys.Credentials.init(gpa.allocator());
    defer credentials.deinit();

    if (try config.var_string("pr.gpg-path", arg_alloc.allocator())) |path| {
        try credentials.gpg(path);
    }

    if (credentials.fetch()) |cred| {
        std.debug.print("cred: {}\n", .{cred});

        credentials.free(cred);
    }

    std.debug.print("pull_request:\n", .{});
    std.debug.print("  title: {s}\n", .{pull_request.title});
    std.debug.print("  description: {s}\n", .{pull_request.description});
    std.debug.print("  source:\n", .{});
    std.debug.print("    url: {s}\n", .{pull_request.source.repo});
    std.debug.print("    branch: {s}\n", .{pull_request.source.branch});
    std.debug.print("  target:\n", .{});
    std.debug.print("    url: {s}\n", .{pull_request.target.repo});
    std.debug.print("    branch: {s}\n", .{pull_request.target.branch});
}

fn build_pr(args: Args, repo: *repository.Repo, config: *repository.GitConfig, alloc: std.mem.Allocator) !pr.PullRequest {
    const description = try read_description(args, alloc);

    var target: pr.Coord = undefined;
    var source: pr.Coord = undefined;

    var target_remote: repository.GitRemote = undefined;
    var source_remote: repository.GitRemote = undefined;

    if (args.target_remote) |remote| {
        target_remote = try repo.remote(remote);
    } else if (config.var_string("pr.target-remote", alloc) catch null) |remote| {
        target_remote = try repo.remote(remote);
        alloc.free(remote);
    } else if (repo.remote("upstream") catch null) |remote| {
        target_remote = remote;
    } else if (repo.remote("origin") catch null) |remote| {
        target_remote = remote;
    } else {
        return Error.MalconfiguredTarget;
    }

    if (args.source_remote) |remote| {
        source_remote = try repo.remote(remote);
    } else if (config.var_string("pr.source-remote", alloc) catch null) |remote| {
        source_remote = try repo.remote(remote);
        alloc.free(remote);
    } else if (repo.remote("origin") catch null) |remote| {
        source_remote = remote;
    } else {
        return Error.MalconfiguredTarget;
    }

    if (args.target_branch) |branch| {
        var buf = try alloc.alloc(u8, branch.len);
        @memcpy(buf, branch);

        target.branch = buf;
    } else if (config.var_string("pr.target-branch", alloc) catch null) |branch| {
        target.branch = branch;
    } else if (try target_remote.head(alloc)) |head| {
        target.branch = head;
    } else {
        var buf = try alloc.alloc(u8, 4);
        @memcpy(buf, "main");
        target.branch = buf;
    }

    if (args.source_branch) |branch| {
        var buf = try alloc.alloc(u8, branch.len);
        @memcpy(buf, branch);

        source.branch = buf;
    } else if (config.var_string("pr.source-branch", alloc) catch null) |branch| {
        source.branch = branch;
    } else if (repo.head() catch null) |head| {
        if (!head.isBranch()) {
            return Error.MalconfiguredSource;
        }

        source.branch = try head.shorthand(alloc);
    } else {
        return Error.MalconfiguredSource;
    }

    target.repo = try target_remote.url(alloc);
    source.repo = try source_remote.url(alloc);

    return .{
        .title = args.title,
        .description = description,
        .source = source,
        .target = target,
    };
}

fn read_description(args: Args, alloc: std.mem.Allocator) ![]const u8 {
    if (args.description) |desc| {
        if (desc.len == 1 and desc[0] == '-') {
            // read stdin
            const file = std.io.getStdIn();
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

            var freader = try Freader.init(file, arena.allocator());
            defer freader.deinit();

            return try freader.to_buffer(alloc);
        } else if (desc.len > 1 and desc[0] == '@') {
            // read file
            const cwd = std.fs.cwd();
            const file = try cwd.openFile(desc[1..], .{});
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

            var freader = try Freader.init(file, arena.allocator());
            defer freader.deinit();

            return try freader.to_buffer(alloc);
        } else {
            var buf = try alloc.alloc(u8, desc.len);
            @memcpy(buf, desc);

            return buf;
        }
    } else {
        return "";
    }
}

fn destroy_pr(pull_request: pr.PullRequest, alloc: std.mem.Allocator) void {
    // title is taken verbaitim from Args

    if (pull_request.description.len != 0) {
        alloc.free(pull_request.description);
    }

    alloc.free(pull_request.source.repo);
    alloc.free(pull_request.source.branch);
    alloc.free(pull_request.target.repo);
    alloc.free(pull_request.target.branch);
}
