const std = @import("std");

/// A simple iterator for testing purposes. It mimics `std.process.ArgIterator`.
pub const SliceIterator = struct {
    args: []const []const u8,
    index: usize = 0,

    pub fn next(self: *@This()) ?[]const u8 {
        if (self.index >= self.args.len) return null;
        const arg = self.args[self.index];
        self.index += 1;
        return arg;
    }
};

/// All errors that can be returned by the parser.
/// app.zig uses this to catch parse errors and exit cleanly (no stack traces).
pub const ParseError = error{
    MissingRequiredArgument,
    TooManyPositionalArguments,
    UnknownFlag,
    MissingFlagValue,
    PositionalAfterFlagNotAllowed,
    InvalidValue,
};

/// Split a flag argument like "--key=value" into the key and optional value.
/// Returns { "key", "value" } or { "key", null }.
fn splitFlag(arg: []const u8) struct { key: []const u8, value: ?[]const u8 } {
    const without_dashes = arg[2..];
    if (std.mem.indexOfScalar(u8, without_dashes, '=')) |eq_pos| {
        return .{
            .key = without_dashes[0..eq_pos],
            .value = without_dashes[eq_pos + 1 ..],
        };
    }
    return .{ .key = without_dashes, .value = null };
}

/// The core comptime parser.
/// Takes a target type `T` and an iterator that has a `next() ?[]const u8` method.
pub fn parseArgs(comptime T: type, allocator: std.mem.Allocator, iter: anytype) ParseError!T {
    _ = allocator;

    var result: T = undefined;

    const info = @typeInfo(T);
    switch (info) {
        .@"struct" => |struct_info| {
            inline for (struct_info.fields) |field| {
                if (field.default_value_ptr) |def_ptr| {
                    const default_val = @as(*align(1) const field.type, @ptrCast(def_ptr)).*;
                    @field(result, field.name) = default_val;
                } else if (field.type == bool) {
                    @field(result, field.name) = false;
                }
            }
        },
        else => @compileError("parseArgs target must be a struct"),
    }

    // 1. Parse all positional arguments first
    var next_arg: ?[]const u8 = iter.next();
    var positional_index: usize = 0;

    while (next_arg) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            // We hit a flag, transition to flag parsing
            break;
        }

        var assigned = false;
        comptime var current_pos = 0;

        inline for (info.@"struct".fields) |field| {
            // Fields without defaults and not bools are positional
            if (field.type != bool and field.default_value_ptr == null) {
                if (current_pos == positional_index) {
                    if (field.type == []const u8) {
                        @field(result, field.name) = arg;
                    } else if (@typeInfo(field.type) == .int) {
                        @field(result, field.name) = std.fmt.parseInt(field.type, arg, 10) catch {
                            std.debug.print("Error: invalid value '{s}' for argument '<{s}>' (expected integer).\n", .{ arg, field.name });
                            return error.InvalidValue;
                        };
                    } else {
                        @compileError("Unsupported type for positional: " ++ @typeName(field.type));
                    }
                    assigned = true;
                }
                current_pos += 1;
            }
        }

        if (!assigned) {
            // Build a list of expected positionals for the error message
            comptime var expected: usize = 0;
            inline for (info.@"struct".fields) |field| {
                if (field.type != bool and field.default_value_ptr == null) {
                    expected += 1;
                }
            }
            std.debug.print("Error: unexpected argument '{s}' (expected {d} positional argument(s)).\n", .{ arg, expected });
            return error.TooManyPositionalArguments;
        }
        positional_index += 1;

        next_arg = iter.next();
    }

    // 2. Parse all flags afterwards
    while (next_arg) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) {
            std.debug.print("Error: unexpected positional argument '{s}' after flags.\n", .{arg});
            std.debug.print("  Hint: positional arguments must come before any --flags.\n", .{});
            return error.PositionalAfterFlagNotAllowed;
        }

        const flag = splitFlag(arg);
        var found = false;

        inline for (info.@"struct".fields) |field| {
            // We consider it a flag if it's a bool OR if it has a default value
            if (field.type == bool or field.default_value_ptr != null) {
                if (std.mem.eql(u8, field.name, flag.key)) {
                    found = true;
                    if (field.type == bool) {
                        // Booleans: --verbose (true), --verbose=true, --verbose=false
                        if (flag.value) |val| {
                            if (std.mem.eql(u8, val, "true")) {
                                @field(result, field.name) = true;
                            } else if (std.mem.eql(u8, val, "false")) {
                                @field(result, field.name) = false;
                            } else {
                                std.debug.print("Error: invalid value '{s}' for '--{s}' (expected 'true' or 'false').\n", .{ val, field.name });
                                return error.InvalidValue;
                            }
                        } else {
                            @field(result, field.name) = true;
                        }
                    } else {
                        // Other types: --retries 5 or --retries=5
                        const val_str = flag.value orelse iter.next() orelse {
                            std.debug.print("Error: flag '--{s}' requires a value.\n", .{field.name});
                            return error.MissingFlagValue;
                        };

                        if (field.type == []const u8) {
                            @field(result, field.name) = val_str;
                        } else if (@typeInfo(field.type) == .int) {
                            @field(result, field.name) = std.fmt.parseInt(field.type, val_str, 10) catch {
                                std.debug.print("Error: invalid value '{s}' for '--{s}' (expected integer).\n", .{ val_str, field.name });
                                return error.InvalidValue;
                            };
                        } else {
                            @compileError("Unsupported type for flag: " ++ @typeName(field.type));
                        }
                    }
                }
            }
        }

        if (!found) {
            std.debug.print("Error: unknown flag '--{s}'.\n", .{flag.key});
            // List valid flags
            std.debug.print("  Available flags:", .{});
            inline for (info.@"struct".fields) |field| {
                if (field.type == bool or field.default_value_ptr != null) {
                    std.debug.print(" --{s}", .{field.name});
                }
            }
            std.debug.print("\n", .{});
            return error.UnknownFlag;
        }

        next_arg = iter.next();
    }

    // 3. Validate that all required positional arguments were provided
    comptime var required_positionals: usize = 0;
    inline for (info.@"struct".fields) |field| {
        if (field.type != bool and field.default_value_ptr == null) {
            required_positionals += 1;
        }
    }

    if (positional_index < required_positionals) {
        std.debug.print("Error: missing required argument(s).\n", .{});
        std.debug.print("  Usage:", .{});
        inline for (info.@"struct".fields) |field| {
            if (field.type != bool and field.default_value_ptr == null) {
                std.debug.print(" <{s}>", .{field.name});
            }
        }
        inline for (info.@"struct".fields) |field| {
            if (field.type == bool or field.default_value_ptr != null) {
                std.debug.print(" [--{s}]", .{field.name});
            }
        }
        std.debug.print("\n", .{});
        return error.MissingRequiredArgument;
    }

    return result;
}

test "parseArgs - initializes default values" {
    const TestArgs = struct {
        verbose: bool, // Should default to false
        retries: u32 = 3, // Should default to 3
    };

    var iter = SliceIterator{ .args = &[_][]const u8{} };
    const args = try parseArgs(TestArgs, std.testing.allocator, &iter);

    try std.testing.expectEqual(false, args.verbose);
    try std.testing.expectEqual(@as(u32, 3), args.retries);
}

test "parseArgs - strict ordering (positionals then flags)" {
    const TestArgs = struct {
        target: []const u8, // Positional 0
        verbose: bool = false, // Flag
        retries: u32 = 3, // Flag
    };

    // Test case 1: Valid strict ordering
    var iter1 = SliceIterator{ .args = &[_][]const u8{
        "my_target", "--verbose", "--retries", "5",
    } };
    const args1 = try parseArgs(TestArgs, std.testing.allocator, &iter1);
    try std.testing.expectEqualStrings("my_target", args1.target);
    try std.testing.expectEqual(true, args1.verbose);
    try std.testing.expectEqual(@as(u32, 5), args1.retries);

    // Test case 2: Invalid interleaved ordering throws error
    var iter2 = SliceIterator{ .args = &[_][]const u8{
        "--verbose", "another_target",
    } };
    const err = parseArgs(TestArgs, std.testing.allocator, &iter2);
    try std.testing.expectError(error.PositionalAfterFlagNotAllowed, err);
}

test "parseArgs - --key=value syntax" {
    const TestArgs = struct {
        target: []const u8,
        verbose: bool = false,
        retries: u32 = 3,
    };

    var iter = SliceIterator{ .args = &[_][]const u8{
        "my_target", "--verbose=true", "--retries=10",
    } };
    const args = try parseArgs(TestArgs, std.testing.allocator, &iter);
    try std.testing.expectEqualStrings("my_target", args.target);
    try std.testing.expectEqual(true, args.verbose);
    try std.testing.expectEqual(@as(u32, 10), args.retries);
}

test "parseArgs - --bool=false" {
    const TestArgs = struct {
        verbose: bool = true,
    };

    var iter = SliceIterator{ .args = &[_][]const u8{"--verbose=false"} };
    const args = try parseArgs(TestArgs, std.testing.allocator, &iter);
    try std.testing.expectEqual(false, args.verbose);
}
