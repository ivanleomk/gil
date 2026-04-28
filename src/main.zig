const std = @import("std");
const teul = @import("teul");

const EchoCmd = struct {
    message: []const u8,

    pub fn run(self: @This()) !void {
        std.debug.print("{s}\n", .{self.message});
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var args_iter = try init.minimal.args.iterateAllocator(allocator);
    defer args_iter.deinit();

    var args_list: std.ArrayList([]const u8) = .empty;
    defer args_list.deinit(allocator);

    while (args_iter.next()) |arg| {
        try args_list.append(allocator, arg);
    }

    const root_cmd = teul.Command{
        .name = "app",
        .description = "A teul starter project",
        .subcommands = &[_]teul.Command{
            .{
                .name = "echo",
                .description = "Echo a message",
                .run_fn = teul.generateWrapper(EchoCmd),
            },
        },
    };

    const app = teul.App.init(root_cmd);
    try app.run(allocator, args_list.items, init);
}
