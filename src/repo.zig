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

    pub fn remote(self: *Self, name: [*]const u8) !GitRemote {
        var r: ?*git2.git_remote = null;

        const succ = git2.git_remote_lookup(&r, self.repo, name);

        if (succ != 0) {
            std.log.err("failed to find remote", .{});
            return Error.git_error;
        }

        return GitRemote.init(r orelse unreachable);
    }

    pub fn config(self: *Self) !GitConfig {
        return GitConfig.init(self);
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

    pub fn url(self: *Self) []const u8 {
        var remote_url = git2.git_remote_url(self.remote);

        return std.mem.span(remote_url);
    }
};

pub const GitConfig = struct {
    config: *git2.git_config,
    fn init(repo: *Repo) !GitConfig {
        var config: ?*git2.git_config = null;

        var succ = git2.git_config_open_default(&config);

        if (succ != 0) {
            var err = git2.git_error_last();
            std.log.err("git error {} - {s}", .{ succ, err.*.message });
            return Error.git_error;
        }

        const c = config orelse unreachable;

        var path: [4096]u8 = undefined;
        @memcpy(path[0..repo.path.len], repo.path);
        const config_path = "config\x00";
        @memcpy(path[repo.path.len..][0..config_path.len], config_path);

        succ = git2.git_config_add_file_ondisk(c, (&path).ptr, git2.GIT_CONFIG_LEVEL_APP, repo.repo, 0);

        if (succ != 0) {
            var err = git2.git_error_last();
            std.log.err("git error {} - {s}", .{ succ, err.*.message });
            return Error.git_error;
        }

        //_ = git2.git_config_foreach(c, dump_keys, null);

        return GitConfig{
            .config = config orelse unreachable,
        };
    }

    pub fn var_string(self: *GitConfig, name: [*:0]const u8, alloc: std.mem.Allocator) !?[]const u8 {
        var entry: ?*git2.git_config_entry = null;
        var succ = git2.git_config_get_entry(&entry, self.config, name);
        if (succ != 0) {
            return null;
        }

        const e = entry orelse unreachable;
        defer {
            if (e.free) |free| {
                free(e);
            }
        }

        const val = std.mem.span(e.value);

        var buf = try alloc.alloc(u8, val.len);

        @memcpy(buf, val);

        return buf;
    }

    pub fn deinit(self: *GitConfig) void {
        git2.git_config_free(self.config);
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

fn dump_keys(entry: [*c]const git2.git_config_entry, _: ?*anyopaque) callconv(.C) c_int {
    std.debug.print("  name: {s}, value: {s}\n", .{
        std.mem.span(entry.*.name),
        std.mem.span(entry.*.value),
    });

    return 0;
}
