const std = @import("std");
const Args = @import("args.zig").Args;

pub fn main() !void {
    // const stdout_file = std.io.getStdOut().writer();
    // const stdout = bw.writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.print("{any}\n", .{gpa.deinit()});
    const allocator = gpa.allocator();

    const stdout = std.io.getStdIn().writer();
    // var bw = std.io.bufferedWriter(stdout);

    _ = try stdout.write(" > ");
    // try bw.flush(); // don't forget to flush!

    const input = try getInput(allocator);
    defer allocator.free(input);

    const args: Args = try sliceToArguments(input, allocator);
    defer args.deinit();

    // Get environment variables from std.os.environ
    const environ = try getEnviron(allocator);

    const pid: std.os.linux.pid_t = @intCast(std.os.linux.fork());
    var status: u32 = 0;
    if (pid == 0) {
        const errors = std.posix.execvpeZ(args.args[0].?, args.args, environ);
        std.debug.print("{any}\n", .{errors});
    } else {
        _ = std.os.linux.waitpid(pid, &status, std.os.linux.W.UNTRACED);
        while (!std.os.linux.W.IFEXITED(status) and !std.os.linux.W.IFSIGNALED(status)) {
            _ = std.os.linux.waitpid(pid, &status, std.os.linux.W.UNTRACED);
        }
    }

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});
    //
    // try bw.flush(); // don't forget to flush!
}

pub fn getEnviron(allocator: std.mem.Allocator) ![*:null]?[*:0]u8 {
    const env = std.os.environ;

    const envCpy = try allocator.alloc(?[*:0]u8, env.len + 1);

    for (0..env.len) |i| {
        envCpy[i] = env[i];
    }

    envCpy[env.len] = null;

    return envCpy[0..env.len :null];
}

pub fn sliceToArguments(buffer: []u8, allocator: std.mem.Allocator) !Args {
    var args: ?Args = null;
    errdefer if (args) |*cArgs| cArgs.deinit();

    var start: u64 = 0;
    for (0..buffer.len) |i| {
        if (std.ascii.isWhitespace(buffer[i])) {
            if (i - start >= 1) {
                if (args) |*cArgs| {
                    try cArgs.addArg(buffer[start..i]);
                } else {
                    args = try Args.init(buffer[start..i], allocator);
                }
            }

            start = i + 1;
        }
    }

    if (buffer.len - start >= 1) {
        if (args) |*cArgs| {
            try cArgs.addArg(buffer[start..buffer.len]);
        } else {
            args = try Args.init(buffer[start..buffer.len], allocator);
        }
    }

    if (args) |cArgs| {
        return cArgs;
    }

    return error.NoArguments;
}

pub fn getInput(allocator: std.mem.Allocator) ![]u8 {
    var buffer: []u8 = try allocator.alloc(u8, 50);
    errdefer allocator.free(buffer);
    const stdin = std.io.getStdIn().reader();

    var start: u64 = 0;
    var len: u64 = 0;

    while (true) {
        var fBStream = std.io.fixedBufferStream(buffer[start..buffer.len]);
        stdin.streamUntilDelimiter(
            fBStream.writer(),
            '\n',
            buffer.len - start,
        ) catch |err| {
            switch (err) {
                error.StreamTooLong => {
                    start = buffer.len;
                    len = buffer.len;

                    const newBuffer = try allocator.alloc(u8, buffer.len + 50);
                    @memcpy(newBuffer, buffer);

                    allocator.free(buffer);
                    buffer = newBuffer;
                },
                else => {
                    return err;
                },
            }
            continue;
        };

        len += fBStream.getWritten().len;
        break;
    }

    const newBuffer = try allocator.alloc(u8, len);
    for (0..len) |i| {
        newBuffer[i] = buffer[i];
    }

    allocator.free(buffer);
    buffer = newBuffer;

    return buffer;
}
