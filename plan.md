## 4. gil (길) - Zero-Ceremony HTTP Client
**Concept:** A high-level HTTP client for Zig that abstracts away the boilerplate of `std.Io` initialization, TLS certificate management, and response body collection. It is designed to make the 90% usecase (fetching JSON, posting forms, downloading files) a one-liner.

In `gil`, the library owns the memory. The user does not pass an allocator. The user does not create an arena. The user does not call `defer res.deinit()`.

### The "One-Liner" API
The primary entry point is the module-level convenience functions, mirroring `httpx.get()`.

```zig
const std = @import("std");
const gil = @import("gil");

pub fn main(init: std.process.Init) !void {
    // 1. Simple GET request. No allocators, no defer.
    const res = try gil.get("https://httpbin.org/get");
    
    // 2. Clean, property-based access
    if (!res.ok) return error.RequestFailed;
    std.debug.print("Status: {d}\n", .{res.status});
    
    // 3. Automatic JSON deserialization
    // The library allocates the struct internally and returns it by value.
    const HttpBinResponse = struct { url: []const u8, origin: []const u8 };
    const data = try res.json(HttpBinResponse);
    std.debug.print("URL: {s}\n", .{data.url});

    // 4. POST request with JSON payload
    const post_res = try gil.post("https://httpbin.org/post", .{
        .json = .{ .title = "foo", .body = "bar" }, // Auto-serializes
        .headers = &.{ .{ "Authorization", "Bearer token123" } },
    });
    try post_res.raiseForStatus();
}
```

### The Context Pattern (Strict Zig Compliance)
If hidden globals violate Zig's "no hidden allocations" principle, we use a `Session` that acts as an arena, but we make it ergonomic. The Session acts as the single memory owner.

```zig
pub fn main(init: std.process.Init) !void {
    // The session owns all memory for all requests made through it.
    // This is the ONLY defer the user writes.
    var session = try gil.Session.init(init.gpa, init.io);
    defer session.deinit();

    // No defer needed for the response!
    const res = try session.get("https://pokeapi.co/api/v2/pokemon/pikachu", .{});
    
    // No defer needed for the parsed JSON!
    const pokemon = try res.json(Pokemon);
    
    std.debug.print("{s}: {d} HP\n", .{ pokemon.name, pokemon.hp });
}
```

### The `Response` Object
Inspired by `httpx` and `fetch`, the `Response` object provides a clean, property-based interface.

| Property / Method | Description |
|---|---|
| `res.status` | The HTTP status code as an integer (e.g., `200`, `404`). |
| `res.ok` | A boolean indicating if the status is in the 200-299 range. |
| `res.text()` | Returns the full response body as a `[]const u8` string. |
| `res.json(T)` | Parses the body into type `T`. |
| `res.json(std.json.Value)` | Parses the body into a generic, dynamically introspectable JSON tree. |
| `res.headers.get("Content-Type")` | Retrieves a specific header value. |
| `res.raiseForStatus()` | Returns an error if `res.ok` is false. |

---