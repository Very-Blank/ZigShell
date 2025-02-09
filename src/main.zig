const std = @import("std");

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

    const arguments = try sliceToArguments(input, allocator);
    defer allocator.free(arguments);
    defer for (arguments) |arg| allocator.free(arg);

    for (arguments) |arg| {
        std.debug.print("|{any}|\n", .{arg});
    }

    const pid: u64 = std.os.linux.fork();
    if (pid == 0) {
        try std.posix.execvpeZ(
            &arguments[0][0],
            &arguments,
            null,
        );
    }

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});
    //
    // try bw.flush(); // don't forget to flush!
}

pub fn sliceToArguments(buffer: []u8, allocator: std.mem.Allocator) ![][]u8 {
    //make this null terminated;
    var arguments: ?[][]u8 = null;
    errdefer if (arguments) |args| allocator.free(args);

    var start: u64 = 0;
    for (0..buffer.len) |i| {
        if (std.ascii.isWhitespace(buffer[i])) {
            if (i - start >= 1) {
                //cut string
                if (arguments) |args| {
                    const length = i - start;
                    const newArgument = try allocator.alloc(u8, length + 1);
                    errdefer allocator.free(newArgument);

                    newArgument[length] = 0;
                    for (start..i) |j| {
                        newArgument[j - start] = buffer[j];
                    }

                    const newArgs = try allocator.alloc([]u8, args.len + 1);

                    newArgs[args.len] = newArgument;
                    for (0..args.len) |j| {
                        newArgs[j] = args[j];
                    }

                    allocator.free(args);

                    arguments = newArgs;
                } else {
                    const length = i - start;
                    const newArgument = try allocator.alloc(u8, length + 1);
                    errdefer allocator.free(newArgument);

                    newArgument[length] = 0;
                    for (start..i) |j| {
                        newArgument[j - start] = buffer[j];
                    }

                    const args = try allocator.alloc([]u8, 1);
                    args[0] = newArgument;

                    arguments = args;
                }
            }

            start = i + 1;
        }
    }

    if (buffer.len - start >= 1) {
        if (arguments) |args| {
            const length = buffer.len - start;
            const newArgument = try allocator.alloc(u8, length + 1);
            errdefer allocator.free(newArgument);

            newArgument[length] = 0;
            for (start..buffer.len) |j| {
                newArgument[j - start] = buffer[j];
            }

            const newArgs = try allocator.alloc([]u8, args.len + 1);

            newArgs[args.len] = newArgument;
            for (0..args.len) |j| {
                newArgs[j] = args[j];
            }

            allocator.free(args);

            arguments = newArgs;
        } else {
            const length = buffer.len - start;
            const newArgument = try allocator.alloc(u8, length + 1);
            errdefer allocator.free(newArgument);

            newArgument[length] = 0;
            for (start..buffer.len) |j| {
                newArgument[j - start] = buffer[j];
            }

            const args = try allocator.alloc([]u8, 1);
            args[0] = newArgument;

            arguments = args;
        }
    }

    if (arguments) |args| {
        return args;
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
                    for (0..buffer.len) |i| {
                        newBuffer[i] = buffer[i];
                    }

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
