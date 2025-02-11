const std = @import("std");
const Args = @import("args.zig").Args;
const Environ = @import("environ.zig").Environ;

// TODO:
// add buildins! "cd" -> chdir(), to change process dir for the parent (shell),
// "help",
// "exit"

// TODO:
// maybe change to execvpeZ to execveZ and get the absolute path yourself?

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
    const environ: Environ = try Environ.init(std.os.environ, allocator);
    defer environ.deinit();

    const pid: std.os.linux.pid_t = @intCast(std.os.linux.fork());
    var status: u32 = 0;
    if (pid == 0) {
        // NOTE: ALSO HERE!!
        const errors = std.posix.execvpeZ(args.args[0].?, args.args, environ.variables);
        std.debug.print("{any}\n", .{errors});
    } else if (pid < 0) {
        return error.ForkFailed;
    } else {
        // NOTE: READ MORE OF THE MAN PAGES FOR THESE
        _ = std.os.linux.waitpid(pid, &status, std.os.linux.W.UNTRACED);
        while (!std.os.linux.W.IFEXITED(status) and !std.os.linux.W.IFSIGNALED(status)) {
            _ = std.os.linux.waitpid(pid, &status, std.os.linux.W.UNTRACED);
        }
    }
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
