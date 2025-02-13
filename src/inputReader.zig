const std = @import("std");

pub const InputReader = struct {
    buffer: ?[]u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) InputReader {
        return .{
            .buffer = null,
            .allocator = allocator,
        };
    }

    pub fn read(self: *InputReader, delimiter: u8) !void {
        var start: u64 = 0;
        var len: u64 = 0;

        var buffer: []u8 = undefined;

        if (self.buffer) |cBuffer| {
            start = cBuffer.len;
            const newBuffer = try self.allocator.alloc(u8, cBuffer.len + 50);
            @memcpy(newBuffer[0..cBuffer.len], cBuffer);

            buffer = newBuffer;
        } else {
            buffer = try self.allocator.alloc(u8, 50);
        }

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

                        const newBuffer = try self.allocator.alloc(u8, buffer.len + 50);
                        @memcpy(newBuffer, buffer);

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

        if (len != buffer.len) {
            const newBuffer = try self.allocator.alloc(u8, len);
            for (0..len) |i| {
                newBuffer[i] = buffer[i];
            }

            self.allocator.free(buffer);
            buffer = newBuffer;
        }

        if (self.buffer) |cBuffer| self.allocator.free(cBuffer);
        self.buffer = buffer;
    }

    pub fn clear(self: *InputReader) void {
        if (self.buffer) |cBuffer| {
            self.allocator.free(cBuffer);
            self.buffer = null;
        }
    }
};
