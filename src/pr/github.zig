const std = @import("std");

pub const Request = struct {
    allocator: std.mem.Allocator,
    title: []const u8,
    description: []const u8,

    source: []const u8,
    source_branch: []const u8,

    target: []const u8,
    target_branch: []const u8,
    bearer: []const u8,

    pub fn request(self: *Request, client: *std.http.Client) !void {
        var url = try std.fmt.allocPrint(self.allocator, "https://api.github.com/repos/{s}/pulls", .{self.target});
        defer self.allocator.free(url);

        var bearer = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.bearer});
        defer self.allocator.free(bearer);

        const uri = try std.Uri.parse(url);
        var headers = std.http.Headers.init(self.allocator);
        try headers.append("Content", "application/vnd.github+json");
        try headers.append("Accept", "application/vnd.github+json");
        try headers.append("Authorization", bearer);
        try headers.append("X-GitHub-Api-Version", "2022-11-28");

        var payload = Payload{
            .title = self.title,
            .body = self.description,
            .head = self.source_branch,
            .head_repo = if (std.mem.eql(u8, self.source, self.target))
                null
            else
                self.source,
            .base = self.target_branch,
        };

        var out = try std.json.stringifyAlloc(self.allocator, payload, .{
            .emit_null_optional_fields = false,
        });
        defer self.allocator.free(out);

        std.debug.print("uri: {s}://{?s}{s}\n", .{ uri.scheme, uri.host, uri.path });
        std.debug.print("payload: '{s}'\n", .{out});

        var req = try client.request(.POST, uri, headers, .{});
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = out.len };
        try req.start();
        try req.writeAll(out);

        std.debug.print("encoding: {}\n", .{req.transfer_encoding});
        try req.finish();

        try req.wait();

        var res_buf: [0x100]u8 = undefined;

        const len = try req.readAll(&res_buf);

        std.debug.print("in : {s}\n", .{out});
        std.debug.print("out: {} {s}\n", .{ req.response.status, res_buf[0..len] });
    }
};

const Payload = struct {
    title: []const u8,
    body: []const u8,
    head: []const u8,
    head_repo: ?[]const u8,
    base: []const u8,
};
