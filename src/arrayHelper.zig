///The string and the sentinel.
pub fn cStrToSliceSentinel(cStr: [*:0]u8) []u8 {
    var i: u64 = 0;
    while (true) : (i += 1) {
        if (cStr[i] == 0) {
            break;
        }
    }

    return cStr[0 .. i + 1];
}

///Only the actual string, sentinel is not included.
pub fn cStrToSlice(cStr: [*:0]u8) []u8 {
    var i: u64 = 0;
    while (true) : (i += 1) {
        if (cStr[i] == 0) {
            break;
        }
    }

    return cStr[0..i];
}
