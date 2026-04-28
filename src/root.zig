const std = @import("std");

/// The Session acts as the single memory owner for requests.
pub const Session = struct {
    gpa: std.mem.Allocator,
    
    pub fn init(gpa: std.mem.Allocator) !Session {
        return Session{
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Session) void {
        _ = self;
    }
};

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
