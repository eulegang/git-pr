const std = @import("std");
const git2 = @cImport({
    @cInclude("git2.h");
});

pub const Error = error{
    git_error,
};

pub const Repo = struct {
    const Self = @This();

    path: []const u8,
    repo: *git2.git_repository,

    pub fn open() !Self {
        _ = git2.git_libgit2_init();

        var path = try discover();
        defer path.deinit();

        var repo: ?*git2.git_repository = null;
        var succ = git2.git_repository_open(&repo, path.cstr());

        if (succ != 0) {
            std.log.err("failed to open git repository", .{});
            return Error.git_error;
        }

        return Self{
            .path = try path.copy(std.heap.c_allocator),
            .repo = repo orelse return Error.git_error,
        };
    }

    pub fn deinit(self: *Self) void {
        std.heap.c_allocator.free(self.path);
        git2.git_repository_free(self.repo);
        _ = git2.git_libgit2_shutdown();
    }

    pub fn remote(self: *Self, name: []const u8) !GitRemote {
        _ = self;
        _ = name;
        git2.git_remote_lookup();
    }

    fn discover() !GitBuf {
        var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        var path: []const u8 = try std.fs.realpath(".", &path_buf);
        path_buf[path.len] = 0;

        var buf = GitBuf.init();
        var succ = git2.git_repository_discover(&buf.buf, @as([*:0]const u8, @ptrCast(path)), 1, null);
        errdefer buf.deinit();

        if (succ != 0) {
            std.log.err("failed to discover repository", .{});
            return Error.git_error;
        }

        return buf;
    }
};

pub const GitRemote = struct {
    const Self = @This();

    remote: *git2.git_remote,

    fn init(remote: *git2.git_remote) GitRemote {
        return GitRemote{
            .remote = remote,
        };
    }

    pub fn deinit(self: *Self) void {
        git2.git_remote_free(self.remote);
    }
};

pub const GitBuf = struct {
    const Self = @This();
    buf: git2.git_buf,

    pub fn init() Self {
        return Self{
            .buf = git2.git_buf{
                .ptr = null,
                .reserved = 0,
                .size = 0,
            },
        };
    }

    pub fn slice(self: *const Self) []const u8 {
        return self.buf.ptr[0..self.buf.size];
    }

    pub fn cstr(self: *const Self) [*:0]const u8 {
        return self.buf.ptr;
    }

    pub fn deinit(self: *Self) void {
        git2.git_buf_dispose(&self.buf);
    }

    pub fn copy(self: *const Self, alloc: std.mem.Allocator) ![]const u8 {
        var buf = try alloc.alloc(u8, self.buf.size);
        @memcpy(buf, self.slice());

        return buf;
    }
};
