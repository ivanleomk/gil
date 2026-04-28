# gil

**Zero-ceremony, ergonomic HTTP client for Zig 0.16.0**

`gil` is a simple, high-level HTTP client library for Zig that aims to minimize boilerplate. It provides a convenient API for making GET and POST requests, handling JSON serialization/deserialization, and automatically decompressing responses (gzip, deflate, zstd).

## Features

- **One-Liner Requests**: Simple `gil.get()` and `gil.post()` for common operations.
- **Ergonomic Headers**: Support for both explicit struct fields (`.{ .name = "...", .value = "..." }`) and tuple shorthand (`.{ "Name", "Value" }`).
- **Seamless JSON Handling**: Pass any Zig struct directly as a JSON payload, and decode responses into specific structs or dynamic `std.json.Value` types.
- **Automatic Decompression**: Transparent support for `gzip`, `deflate`, and `zstd` out of the box.

## Why `gil`? (Zig vs Gil)

Here is a comparison of making a simple JSON POST request.

**With Standard Zig (`std.http.Client`):**
```zig
var client = std.http.Client{ .allocator = allocator };
defer client.deinit();

const uri = try std.Uri.parse("https://httpbin.org/post");
var buf: [4096]u8 = undefined;
var req = try client.open(.POST, uri, .{ .server_header_buffer = &buf });
defer req.deinit();

req.transfer_encoding = .chunked;
try req.send();

// Serialize JSON manually to the request writer
try std.json.stringify(.{ .hello = "world" }, .{}, req.writer());
try req.finish();
try req.wait();

// Checking status
if (req.response.status != .ok) return error.RequestFailed;

// Reading body requires a separate allocator or bounded buffer
const body = try req.reader().readAllAlloc(allocator, 1024 * 1024);
defer allocator.free(body);
```

**With `gil`:**
```zig
const res = try gil.post("https://httpbin.org/post", .{
    .json = .{ .hello = "world" }
});
try res.raiseForStatus();

// res.body is automatically fully buffered, decompressed, and available!
```

## Installation

Add `gil` to your `build.zig.zon`:

```sh
zig fetch --save https://github.com/ivanleomk/gil/archive/refs/tags/v0.1.0.tar.gz
```

Then add it to your `build.zig`:

```zig
const gil_dep = b.dependency("gil", .{
    .target = target,
    .optimize = optimize,
});

// For an executable
exe.root_module.addImport("gil", gil_dep.module("gil"));
```

## Quick Start

### Basic GET Request

```zig
const std = @import("std");
const gil = @import("gil");

pub fn main(init: std.process.Init) !void {
    const res = try gil.get("https://httpbin.org/get", .{});
    try res.raiseForStatus();

    std.debug.print("Response: {s}\n", .{res.body});
}
```

### POST JSON with Headers

```zig
const std = @import("std");
const gil = @import("gil");

pub fn main(init: std.process.Init) !void {
    const payload = .{
        .username = "zig_user",
        .role = "admin",
    };

    const res = try gil.post("https://httpbin.org/post", .{
        .json = payload,
        .headers = &.{
            .{ "Authorization", "Bearer my-token" }, // Tuple syntax!
        },
    });
    try res.raiseForStatus();
    
    // Parse response dynamically
    const parsed = try res.json(std.json.Value);
    std.debug.print("Parsed JSON: {any}\n", .{parsed});
}
```

### Dynamic Environment Variables in Zig 0.16.0

`gil` is built for Zig 0.16.0, where environment variables are cleanly accessible via `std.process.Init`:

```zig
pub fn main(init: std.process.Init) !void {
    const api_key = init.environ_map.get("MY_API_KEY") orelse return error.MissingKey;
    // ... use api_key in your gil requests
}
```

### Advanced Example: Gemini API

Here is a full example of interacting with the Google Gemini API, including dynamic JSON parsing and saving the response to a file using the Zig 0.16.0 `std.Io` interface.

```zig
const std = @import("std");
const gil = @import("gil");

pub fn main(init: std.process.Init) !void {
    // In Zig 0.16.0, we can access the environment map directly from Init!
    const api_key = init.environ_map.get("GOOGLE_API_KEY") orelse {
        std.debug.print("Failed to read GEMINI_API_KEY from environment.\n", .{});
        return;
    };

    const payload = .{ .contents = &.{.{ .parts = &.{.{ .text = "Tell me a short 1-sentence joke about programming in Zig." }} }} };

    std.debug.print("Sending request to Gemini...\n", .{});

    // Make the POST request
    const res = try gil.post("https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent", .{ 
        .json = payload, 
        .headers = &.{
            .{ "Content-Type", "application/json" },
            .{ "x-goog-api-key", api_key },
        } 
    });

    try res.raiseForStatus();

    // Parse the response dynamically!
    const parsed = try res.json(std.json.Value);

    // Introspect the JSON dynamically
    // The Gemini Response looks like: { "candidates": [ { "content": { "parts": [ { "text": "..." } ] } } ] }
    const root_obj = parsed.object;
    if (root_obj.get("candidates")) |candidates| {
        const candidate = candidates.array.items[0].object;
        const content = candidate.get("content").?.object;
        const parts = content.get("parts").?.array;
        const text = parts.items[0].object.get("text").?.string;

        std.debug.print("\n✨ Gemini says:\n{s}\n", .{text});
    } else {
        std.debug.print("Unexpected response: {s}\n", .{res.body});
    }

    // Write the raw response to a file
    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = "response.json",
        .data = res.body,
    });
    std.debug.print("\n📝 Raw JSON response saved to response.json!\n", .{});
}
```

## AI Agent Skill (Vercel v0 / Claude)

You can provide the following instructions to an AI agent to teach it how to use `gil` in your codebase.

**Skill Prompt:**
```markdown
When I ask you to make HTTP requests in Zig, you should use the `gil` library.
The `gil` library exposes a zero-ceremony API for HTTP operations in Zig 0.16.0.

Rules for using `gil`:
1. Use `const res = try gil.get(url, .{ .headers = &.{ .{ "Key", "Value" } } })` for GET requests.
2. Use `const res = try gil.post(url, .{ .json = my_payload, .headers = &.{ .{ "Key", "Value" } } })` for POST requests.
3. Call `try res.raiseForStatus()` immediately after the request to ensure success.
4. If you need to access the raw response body, read `res.body`.
5. If you need to parse JSON, use `const parsed = try res.json(MyStruct)` or `const parsed = try res.json(std.json.Value)` for dynamic introspection.
6. The `gil` library handles `std.process.Init` automatically if using module-level one-liners, but make sure your `main` uses the Zig 0.16.0 signature: `pub fn main(init: std.process.Init) !void`.
```
