//! root module to re-export everything in this module.

pub const debug = @import("debug.zig");

test {
    _ = debug;
}
