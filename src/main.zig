const std = @import("std");

pub fn main() !void {
    // const stdout_file = std.io.getStdOut().writer();
    // const stdout = bw.writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.print("{any}", .{gpa.deinit()});
    const allocator = gpa.allocator();

    const stdout = std.io.getStdIn().writer();
    // var bw = std.io.bufferedWriter(stdout);

    _ = try stdout.write(" > ");
    // try bw.flush(); // don't forget to flush!

    const input = try getInput(allocator);
    defer allocator.free(input);

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});
    //
    // try bw.flush(); // don't forget to flush!
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
    std.debug.print("{s}\n", .{buffer[0..len]});

    //SLICE OFF THE UNUSED PART!!!

    return buffer;
}
