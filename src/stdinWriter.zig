const std = @import("std");

pub fn write(self: std.fs.File, bytes: []const u8) std.posix.WriteError!usize {
    return std.posix.write(self.handle, bytes);
}

pub const StdinWriter = std.io.GenericWriter(std.fs.File, std.posix.WriteError, write);

pub fn getWriter() StdinWriter {
    return StdinWriter{ .context = std.fs.File{ .handle = std.posix.STDIN_FILENO } };
}
