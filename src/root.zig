const std = @import("std");

/// The Session acts as the single memory owner for requests.
pub const Session = struct {
    arena: std.heap.ArenaAllocator,
    client: std.http.Client,

    pub fn init(gpa: std.mem.Allocator, io: std.Io) Session {
        const arena = std.heap.ArenaAllocator.init(gpa);
        const client = std.http.Client{ .allocator = gpa, .io = io };
        return Session{
            .arena = arena,
            .client = client,
        };
    }

    pub fn deinit(self: *Session) void {
        self.client.deinit();
        self.arena.deinit();
    }

    pub fn get(self: *Session, url: []const u8, options: anytype) !Response {
        const uri = try std.Uri.parse(url);
        const allocator = self.arena.allocator();
        
        var extra_headers_list = std.ArrayList(std.http.Header).empty;
        if (@hasField(@TypeOf(options), "headers")) {
            inline for (options.headers) |h| {
                try extra_headers_list.append(allocator, .{ .name = h.name, .value = h.value });
            }
        }

        var req = try self.client.request(.GET, uri, .{
            .extra_headers = extra_headers_list.items,
        });
        defer req.deinit();

        try req.sendBodiless();
        
        var redirect_buf: [8192]u8 = undefined;
        var response = try req.receiveHead(&redirect_buf);

        // Copy headers before reading body
        var header_list = std.ArrayList(std.http.Header).empty;
        var it = response.head.iterateHeaders();
        while (it.next()) |h| {
            try header_list.append(allocator, .{
                .name = try allocator.dupe(u8, h.name),
                .value = try allocator.dupe(u8, h.value),
            });
        }

        var reader = response.reader(&.{});
        const body = try reader.allocRemaining(allocator, .unlimited);
        const ok = @intFromEnum(response.head.status) >= 200 and @intFromEnum(response.head.status) < 300;

        return Response{
            .status = @intFromEnum(response.head.status),
            .ok = ok,
            .body = body,
            .allocator = allocator,
            .headers = Headers{ .items = try header_list.toOwnedSlice(allocator) },
        };
    }

    pub fn post(self: *Session, url: []const u8, options: anytype) !Response {
        const uri = try std.Uri.parse(url);
        const allocator = self.arena.allocator();
        
        var extra_headers_list = std.ArrayList(std.http.Header).empty;
        if (@hasField(@TypeOf(options), "headers")) {
            inline for (options.headers) |h| {
                try extra_headers_list.append(allocator, .{ .name = h.name, .value = h.value });
            }
        }

        var req = try self.client.request(.POST, uri, .{
            .extra_headers = extra_headers_list.items,
        });
        defer req.deinit();

        if (@hasField(@TypeOf(options), "json")) {
            const payload = try std.json.Stringify.valueAlloc(allocator, options.json, .{});
            req.transfer_encoding = .{ .content_length = payload.len };
            try req.sendBodyComplete(payload);
        } else {
            try req.sendBodiless();
        }
        
        var redirect_buf: [8192]u8 = undefined;
        var response = try req.receiveHead(&redirect_buf);

        // Copy headers before reading body
        var header_list = std.ArrayList(std.http.Header).empty;
        var it = response.head.iterateHeaders();
        while (it.next()) |h| {
            try header_list.append(allocator, .{
                .name = try allocator.dupe(u8, h.name),
                .value = try allocator.dupe(u8, h.value),
            });
        }

        var reader = response.reader(&.{});
        const body = try reader.allocRemaining(allocator, .unlimited);
        const ok = @intFromEnum(response.head.status) >= 200 and @intFromEnum(response.head.status) < 300;

        return Response{
            .status = @intFromEnum(response.head.status),
            .ok = ok,
            .body = body,
            .allocator = allocator,
            .headers = Headers{ .items = try header_list.toOwnedSlice(allocator) },
        };
    }
};

pub const Headers = struct {
    items: []const std.http.Header,

    pub fn get(self: Headers, name: []const u8) ?[]const u8 {
        for (self.items) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, name)) {
                return header.value;
            }
        }
        return null;
    }
};

pub const Response = struct {
    status: u16,
    ok: bool,
    body: []const u8,
    allocator: std.mem.Allocator,
    headers: Headers,

    pub fn text(self: *const Response) []const u8 {
        return self.body;
    }

    pub fn json(self: *const Response, comptime T: type) !T {
        const parsed = try std.json.parseFromSlice(T, self.allocator, self.body, .{ .ignore_unknown_fields = true });
        return parsed.value;
    }

    pub fn raiseForStatus(self: *const Response) !void {
        if (!self.ok) {
            return error.RequestFailed;
        }
    }
};

// Module-level convenience functions mirroring httpx.get()
// This requires a global session or hidden allocations, which plan.md mentions might violate strict zig compliance.
// But plan.md specifies them: "The primary entry point is the module-level convenience functions, mirroring httpx.get()."
// We would need a threadlocal or global allocator and Io.
// For now, let's keep it to Session as we'll need to figure out the global state later.
