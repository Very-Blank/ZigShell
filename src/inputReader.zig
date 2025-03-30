const std = @import("std");

pub const InputReader = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) InputReader {
        return .{
            .allocator = allocator,
        };
    }

    /// Caller owns the memory
    pub fn read(self: *const InputReader, delimiter: u8) ![]u8 {
        var start: u64 = 0;
        var len: u64 = 0;

        var buffer: []u8 = try self.allocator.alloc(u8, 64);

        errdefer self.allocator.free(buffer);

        const stdin = std.io.getStdIn().reader();

        while (true) {
            var fBStream = std.io.fixedBufferStream(buffer[start..buffer.len]);
            stdin.streamUntilDelimiter(
                fBStream.writer(),
                delimiter,
                buffer.len - start,
            ) catch |err| {
                switch (err) {
                    error.StreamTooLong => {
                        start = buffer.len;
                        len = buffer.len;

                        const newBuffer = try self.allocator.alloc(u8, buffer.len * 2);
                        @memcpy(newBuffer[0..buffer.len], buffer);

                        self.allocator.free(buffer);
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

        if (len == 0) {
            return error.NoInput;
        }

        if (len != buffer.len) {
            const newBuffer = try self.allocator.alloc(u8, len);
            for (0..len) |i| {
                newBuffer[i] = buffer[i];
            }

            self.allocator.free(buffer);
            buffer = newBuffer;
        }

        return buffer;
    }
};
