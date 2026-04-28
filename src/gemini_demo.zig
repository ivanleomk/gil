const std = @import("std");
const gil = @import("root.zig");

pub fn main(init: std.process.Init) !void {
    // In Zig 0.16.0, we can access the environment map directly from Init!
    const api_key = init.environ_map.get("GOOGLE_API_KEY") orelse {
        std.debug.print("Failed to read GEMINI_API_KEY from environment.\n", .{});
        return;
    };

    const payload = .{ .contents = &.{.{ .parts = &.{.{ .text = "Tell me a short 1-sentence joke about programming in Zig." }} }} };

    std.debug.print("Sending request to Gemini 2.5 Flash...\n", .{});

    // Make the POST request
    const res = try gil.post("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent", .{
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
}
