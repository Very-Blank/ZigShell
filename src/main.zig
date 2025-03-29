const std = @import("std");
const builtin = @import("builtin");
const CommandQueue = @import("commandQueue.zig").CommandQueue;
const InputReader = @import("inputReader.zig").InputReader;
const Environ = @import("environ.zig").Environ;
const Executer = @import("executer.zig").Executer;
const stdinWriter = @import("stdinWriter.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn write(self: std.fs.File, bytes: []const u8) std.posix.WriteError!usize {
    return std.posix.write(self.handle, bytes);
}

pub fn main() !void {
    const allocator: std.mem.Allocator, const is_debug: bool = gpa: {
        if (builtin.target.os.tag == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };

    defer if (is_debug) {
        std.debug.print("Debug allocator: {any}\n", .{debug_allocator.deinit()});
    };

    // const stdout: std.io.AnyWriter() = std.io.getStdIn().writer();

    // const stdout: std.io.AnyWriter = std.io.GenericWriter(std.io.getStdIn(), std.posix.WriteError, write);

    var inputReader = InputReader.init(allocator);
    defer inputReader.clear();

    var commandQueue: CommandQueue = CommandQueue.init(allocator);
    defer commandQueue.deinit();

    const environ: Environ = try Environ.init(std.os.environ, allocator);
    defer environ.deinit();

    var executer: Executer = try Executer.init(allocator);
    defer executer.deinit();

    // var delimeter: u8 = '\n';
    const stdin: stdinWriter.StdinWriter = stdinWriter.getWriter();

    while (true) {
        _ = try stdin.write(" > ");
        inputReader.read('\n') catch {
            continue;
        };

        // NOTE: Unreachable because it's an error for the InputReader to be empty,
        //       which is catched above so this is save.
        commandQueue.parse(if (inputReader.buffer) |cBuffer| cBuffer else unreachable) catch {
            _ = try stdin.write("SyntaxError, while parsing input.\n");
        };

        executer.executeCommands(&commandQueue, &environ, &stdin) catch |err| {
            switch (err) {
                error.Exit, error.ChildExit => break,
                // These errors are okay to happen
                error.InvalidPath => {},
                else => return err,
            }
        };

        inputReader.clear();
        commandQueue.deinit();
    }
}
