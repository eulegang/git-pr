const std = @import("std");
const credsys = @import("credsys");

const github = @import("github.zig");

const repo = @import("root").repository;

pub const Error = error{ InvalidSchema, NoPath, DifferentDomains, UnknownHost, InvalidCredentials };

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

pub const Requester = struct {
    alloc: std.mem.Allocator,
    client: std.http.Client,
    credentials: *credsys.Credentials,
    config: *repo.GitConfig,

    pub fn init(alloc: std.mem.Allocator, config: *repo.GitConfig, credentials: *credsys.Credentials) Requester {
        var client = std.http.Client{ .allocator = alloc };
        return Requester{
            .alloc = alloc,
            .client = client,
            .config = config,
            .credentials = credentials,
        };
    }

    pub fn deinit(self: *Requester) void {
        self.client.deinit();
    }

    pub fn request_pull(self: *Requester, request: PullRequest) !void {
        var src = try Route.from(request.source.repo);
        var dst = try Route.from(request.target.repo);

        if (!std.mem.eql(u8, src.hostname, dst.hostname)) {
            return Error.DifferentDomains;
        }

        if (std.mem.eql(u8, src.hostname, "github.com")) {
            var creds = self.credentials.fetch() orelse return Error.InvalidCredentials;
            defer self.credentials.free(creds);

            var req = github.Request{
                .allocator = self.alloc,
                .title = request.title,
                .description = request.description,
                .source = src.path,
                .source_branch = request.source.branch,
                .target = dst.path,
                .target_branch = request.target.branch,
                .bearer = creds.token,
            };

            try req.request(&self.client);
        } else {
            return Error.UnknownHost;
        }

        std.debug.print("host: {s}\n", .{src.hostname});

        std.debug.print("request: {s}\n", .{request.title});
    }
};

const Route = struct {
    hostname: []const u8,
    path: []const u8,

    fn from(buf: []const u8) !Route {
        const rest = try strip_prot(buf);
        const offset = std.mem.indexOfScalar(u8, rest, '/') orelse return Error.NoPath;

        var hostname = rest[0..offset];
        var path = rest[offset + 1 ..];

        return Route{
            .hostname = hostname,
            .path = path,
        };
    }

    fn strip_prot(buf: []const u8) ![]const u8 {
        if (std.mem.startsWith(u8, buf, "https://")) {
            return buf[7..];
        } else if (std.mem.startsWith(u8, buf, "ssh://")) {
            return buf[6..];
        } else {
            return Error.InvalidSchema;
        }
    }
};
