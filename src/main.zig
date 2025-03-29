const std = @import("std");
const builtin = @import("builtin");
const ArgsQueue = @import("argsQueue.zig").ArgsQueue;

const InputReader = @import("inputReader.zig").InputReader;
const Environ = @import("environ.zig").Environ;
const Executer = @import("executer.zig").Executer;
const stdinWriter = @import("stdinWriter.zig");
const Args = @import("args.zig").Args;

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn write(self: std.fs.File, bytes: []const u8) std.posix.WriteError!usize {
    return std.posix.write(self.handle, bytes);
}

pub fn main() !void {
    const allocator: std.mem.Allocator, const is_debug: bool = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };

    defer if (is_debug) {
        std.debug.print("Debug allocator: {any}\n", .{debug_allocator.deinit()});
    };

    const inputReader = InputReader.init(allocator);
    const argsQueue = ArgsQueue.init(allocator);

    // Helper function to get the enviroment variables to C strings
    const environ: Environ = try Environ.init(std.os.environ, allocator);
    defer environ.deinit();

    var executer: Executer = try Executer.init(allocator);
    defer executer.deinit();

    const stdin: stdinWriter.StdinWriter = stdinWriter.getWriter();

    while (true) {
        _ = try stdin.write(" > ");
        const buffer: []u8 = inputReader.read('\n') catch {
            continue;
        };
        defer allocator.free(buffer);

        const args: []Args = argsQueue.parse(buffer) catch {
            _ = try stdin.write("SyntaxError while parsing input.\n");
            continue;
        };
        defer {
            for (args) |arg| {
                arg.deinit();
            }

            allocator.free(args);
        }

        executer.executeArgs(args, &environ, &stdin) catch |err| {
            switch (err) {
                error.Exit, error.ChildExit => break,
                // These errors are okay to happen
                error.InvalidPath => {},
                else => return err,
            }
        };
    }
}
