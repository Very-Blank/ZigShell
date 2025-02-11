const std = @import("std");

pub const Environ = struct {
    variables: [*:null]?[*:0]u8,
    len: u64,
    allocator: std.mem.Allocator,

    pub fn init(env: [][*:0]u8, allocator: std.mem.Allocator) !Environ {
        const envCpy = try allocator.alloc(?[*:0]u8, env.len + 1);

        for (0..env.len) |i| {
            var j: u64 = 0;
            while (true) : (j += 1) {
                if (env[i][j] == 0) {
                    break;
                }
            }
            envCpy[i] = try allocator.dupeZ(u8, env[i][0..j]);
        }

        envCpy[env.len] = null;

        return .{
            .variables = envCpy[0..env.len :null],
            .len = env.len + 1,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *const Environ) void {
        for (self.variables[0 .. self.len - 1]) |variable| {
            if (variable) |cVariable| {
                var i: u64 = 0;
                while (true) : (i += 1) {
                    if (cVariable[i] == 0) {
                        break;
                    }
                }
                self.allocator.free(cVariable[0 .. i + 1]);
            }
        }
        self.allocator.free(self.variables[0..self.len]);
    }
};
