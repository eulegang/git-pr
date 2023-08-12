const std = @import("std");

pub const Freader = struct {
    const Entry = struct {
        const SIZE: usize = 4096;
        const MASK: usize = SIZE - 1;

        next: ?*Entry,
        buf: [SIZE]u8,
    };

    file: std.fs.File,
    alloc: std.mem.Allocator,
    root: *Entry,
    len: usize,

    pub fn init(file: std.fs.File, alloc: std.mem.Allocator) !Freader {
        var entry = try alloc.create(Entry);
        entry.next = null;

        return Freader{
            .file = file,
            .alloc = alloc,
            .root = entry,
            .len = 0,
        };
    }

    pub fn deinit(self: *Freader) void {
        self.file.close();

        var entry: ?*Entry = self.root;

        while (entry) |e| {
            const next = e.next;
            self.alloc.destroy(e);
            entry = next;
        }
    }

    pub fn to_buffer(self: *Freader, alloc: std.mem.Allocator) ![]const u8 {
        var buf = try alloc.alloc(u8, self.len);
        var cur = self.root;

        var i: usize = 0;
        while (i != self.len) : (i += Entry.SIZE) {
            const len = @min(Entry.SIZE, self.len - i);

            @memcpy(buf[i..][0..len], cur.buf[0..len]);
        }

        return buf;
    }
};
