const std = @import("std");
const parser = @import("parser.zig");

/// A node in the CLI routing tree.
pub const Command = struct {
    name: []const u8,
    description: []const u8 = "",

    /// A list of subcommands. If this is not empty, this command acts as a group (e.g. `gcp`).
    subcommands: []const Command = &[_]Command{},

    /// The type-erased wrapper function.
    /// It takes an allocator, the remaining raw string arguments, and the Init struct.
    /// If this is null, the command is just a routing group and cannot be executed directly.
    run_fn: ?*const fn(allocator: std.mem.Allocator, args: []const []const u8, init: std.process.Init) anyerror!void = null,
};

/// A comptime helper to generate the `run_fn` wrapper for a given user struct.
/// The `CmdStruct` must have fields defining its arguments and a `pub fn run(...) !void` method.
pub fn generateWrapper(comptime CmdStruct: type) *const fn(std.mem.Allocator, []const []const u8, std.process.Init) anyerror!void {
    return struct {
        fn wrapper(allocator: std.mem.Allocator, args: []const []const u8, init: std.process.Init) anyerror!void {
            // We use the SliceIterator so we can parse a simple array of strings!
            var iter = parser.SliceIterator{ .args = args };
            
            // 1. Parse the remaining strings into the user's struct
            const parsed_args = try parser.parseArgs(CmdStruct, allocator, &iter);
            
            // 2. Execute the user's logic!
            // We use comptime reflection to check if run() takes 1 or 2 arguments.
            const RunFn = @TypeOf(CmdStruct.run);
            const run_info = @typeInfo(RunFn).@"fn";
            
            if (run_info.params.len == 1) {
                try parsed_args.run();
            } else if (run_info.params.len == 2) {
                try parsed_args.run(init);
            } else {
                @compileError("run() must take 0 or 1 additional argument (init: std.process.Init)");
            }
        }
    }.wrapper;
}
