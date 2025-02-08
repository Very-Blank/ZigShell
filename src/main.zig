const std = @import("std");

pub fn main() !void {
    // const stdout_file = std.io.getStdOut().writer();
    // const stdout = bw.writer();

    while (true) {
        const stdin = std.io.getStdIn().reader();
        const stdout = std.io.getStdIn().writer();
        // var bw = std.io.bufferedWriter(stdout);

        _ = try stdout.write(" > ");
        // try bw.flush(); // don't forget to flush!

        var buf: [10]u8 = .{0} ** 10;
        var fBStream = std.io.fixedBufferStream(buf[0..10]);
        try stdin.streamUntilDelimiter(
            fBStream.writer(),
            '\n',
            10,
        );

        const output = fBStream.getWritten();
        std.debug.print("{s}\n", .{output});
    }

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});
    //
    // try bw.flush(); // don't forget to flush!
}
