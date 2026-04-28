const std = @import("std");
const gil = @import("root.zig");

test "basic get request" {
    var threaded_io = std.Io.Threaded.init(std.testing.allocator, .{});
    // No deinit needed for Threaded io in zig 0.16.0? Wait, let's just leave it or see if it leaks.
    
    var session = gil.Session.init(std.testing.allocator, threaded_io.io());
    defer session.deinit();

    const res = try session.get("https://httpbin.org/get", .{});
    
    try std.testing.expect(res.ok);
    try std.testing.expectEqual(200, res.status);
    
    // We expect the text body to be valid JSON
    const body = res.text();
    try std.testing.expect(body.len > 0);
}

test "get request with custom headers" {
    var threaded_io = std.Io.Threaded.init(std.testing.allocator, .{});
    
    var session = gil.Session.init(std.testing.allocator, threaded_io.io());
    defer session.deinit();

    const res = try session.get("https://httpbin.org/headers", .{
        .headers = &.{
            .{ .name = "X-My-Custom-Header", .value = "FooBar" }
        }
    });
    
    try std.testing.expect(res.ok);
    try std.testing.expectEqual(200, res.status);

    const HttpBinHeadersResponse = struct {
        headers: struct {
            @"X-My-Custom-Header": []const u8,
        },
    };

    const parsed = try res.json(HttpBinHeadersResponse);
    try std.testing.expectEqualStrings("FooBar", parsed.headers.@"X-My-Custom-Header");
}

test "post request with json payload" {
    var threaded_io = std.Io.Threaded.init(std.testing.allocator, .{});
    
    var session = gil.Session.init(std.testing.allocator, threaded_io.io());
    defer session.deinit();

    const payload = .{ .title = "foo", .body = "bar" };

    const res = try session.post("https://httpbin.org/post", .{
        .json = payload,
        .headers = &.{
            .{ .name = "Content-Type", .value = "application/json" }
        }
    });
    
    try std.testing.expect(res.ok);
    try std.testing.expectEqual(200, res.status);
    
    // Test json deserialization
    const HttpBinPostResponse = struct {
        json: struct {
            title: []const u8,
            body: []const u8,
        },
    };

    const parsed = try res.json(HttpBinPostResponse);
    try std.testing.expectEqualStrings("foo", parsed.json.title);
    try std.testing.expectEqualStrings("bar", parsed.json.body);
}
