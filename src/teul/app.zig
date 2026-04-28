const std = @import("std");
const command = @import("command.zig");

pub const App = struct {
    root: command.Command,

    pub fn init(root: command.Command) App {
        return .{ .root = root };
    }

    /// Walks the command tree using the provided arguments and executes the target command.
    pub fn run(self: App, allocator: std.mem.Allocator, args: []const []const u8, app_init: std.process.Init) !void {
        if (args.len == 0) return;

        // Skip the executable name (e.g. `dogu`)
        var current_args = args[1..];
        var current_cmd: *const command.Command = &self.root;

        // 2. Walk the tree!
        while (current_args.len > 0) {
            const next_arg = current_args[0];

            // If we hit a flag, it belongs to the current command, so we stop routing.
            if (std.mem.startsWith(u8, next_arg, "--")) {
                break;
            }

            var found_subcommand = false;
            for (current_cmd.subcommands) |*sub| {
                if (std.mem.eql(u8, sub.name, next_arg)) {
                    current_cmd = sub;
                    current_args = current_args[1..];
                    found_subcommand = true;
                    break;
                }
            }

            // If it's not a subcommand, it must be a positional argument for the current command.
            if (!found_subcommand) {
                break;
            }
        }

        // 3. Execute the leaf command
        if (current_cmd.run_fn) |run_fn| {
            // We pass the remaining strings directly to the generated wrapper!
            run_fn(allocator, current_args, app_init) catch |err| {
                // Parse errors already printed a clean message — just exit.
                switch (err) {
                    error.MissingRequiredArgument,
                    error.TooManyPositionalArguments,
                    error.UnknownFlag,
                    error.MissingFlagValue,
                    error.PositionalAfterFlagNotAllowed,
                    error.InvalidValue,
                    => std.process.exit(1),
                    else => return err,
                }
            };
        } else {
            // They targeted a "Group" command but didn't provide a valid subcommand.
            self.printUsage(current_cmd);
        }
    }

    fn printUsage(self: App, cmd: *const command.Command) void {
        _ = self;
        std.debug.print("\n  {s}", .{cmd.name});
        if (cmd.description.len > 0) {
            std.debug.print(" — {s}", .{cmd.description});
        }
        std.debug.print("\n\n", .{});

        if (cmd.subcommands.len > 0) {
            std.debug.print("  COMMANDS:\n", .{});
            for (cmd.subcommands) |sub| {
                std.debug.print("    {s: <16}{s}\n", .{ sub.name, sub.description });
            }
            std.debug.print("\n", .{});
        }

        std.debug.print("  Run '{s} <command> --help' for more information.\n\n", .{cmd.name});
    }
};
