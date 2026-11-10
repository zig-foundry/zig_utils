//! Terminal ANSI colors, text styles, and formatted stderr output helpers.

const std = @import("std");

// === Enums ===

/// Standard and bright ANSI foreground colors for terminal output.
pub const Color = enum {
    default,
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
    /// Returns the ANSI escape sequence string for this foreground color.
    pub fn ansiCode(self: Color) []const u8 {
        return switch (self) {
            .default => "\x1b[39m",
            .black => "\x1b[30m",
            .red => "\x1b[31m",
            .green => "\x1b[32m",
            .yellow => "\x1b[33m",
            .blue => "\x1b[34m",
            .magenta => "\x1b[35m",
            .cyan => "\x1b[36m",
            .white => "\x1b[37m",
            .bright_black => "\x1b[90m",
            .bright_red => "\x1b[91m",
            .bright_green => "\x1b[92m",
            .bright_yellow => "\x1b[93m",
            .bright_blue => "\x1b[94m",
            .bright_magenta => "\x1b[95m",
            .bright_cyan => "\x1b[96m",
            .bright_white => "\x1b[97m",
        };
    }
};
/// ANSI text formatting styles for terminal output.
pub const Style = enum {
    reset,
    bold,
    dim,
    italic,
    underline,
    /// Returns the ANSI escape sequence string for this text style.
    pub fn ansiCode(self: Style) []const u8 {
        return switch (self) {
            .reset => "\x1b[0m",
            .bold => "\x1b[1m",
            .dim => "\x1b[2m",
            .italic => "\x1b[3m",
            .underline => "\x1b[4m",
        };
    }
};

// === Printing Functions ===

/// Prints formatted text to stderr in color, then resets terminal styling.
pub fn cprint(color: Color, comptime fmt: []const u8, args: anytype) void {
    std.debug.print("{s}" ++ fmt ++ "{s}", .{color.ansiCode()} ++ args ++ .{Style.reset.ansiCode()});
}

/// Prints formatted text to stderr with both style and color, then resets styling.
pub fn sprint(style: Style, color: Color, comptime fmt: []const u8, args: anytype) void {
    std.debug.print(
        "{s}{s}" ++ fmt ++ "{s}",
        .{ style.ansiCode(), color.ansiCode() } ++ args ++ .{Style.reset.ansiCode()},
    );
}

/// Prints a cyan [INFO] message followed by a newline.
pub fn info(comptime fmt: []const u8, args: anytype) void {
    sprint(.bold, .cyan, "[INFO] ", .{});
    std.debug.print(fmt ++ "\n", args);
}

/// Prints a green [OK] message followed by a newline.
pub fn success(comptime fmt: []const u8, args: anytype) void {
    sprint(.bold, .green, "[OK] ", .{});
    std.debug.print(fmt ++ "\n", args);
}

/// Prints a yellow [WARN] message followed by a newline.
pub fn warn(comptime fmt: []const u8, args: anytype) void {
    sprint(.bold, .yellow, "[WARN] ", .{});
    std.debug.print(fmt ++ "\n", args);
}

/// Prints a red [ERROR] message followed by a newline.
pub fn err(comptime fmt: []const u8, args: anytype) void {
    sprint(.bold, .red, "[ERROR] ", .{});
    std.debug.print(fmt ++ "\n", args);
}

// === Unit Tests ===

test "Color and Style ANSI escape codes" {
    try std.testing.expectEqualStrings("\x1b[31m", Color.red.ansiCode());
    try std.testing.expectEqualStrings("\x1b[92m", Color.bright_green.ansiCode());
    try std.testing.expectEqualStrings("\x1b[1m", Style.bold.ansiCode());
    try std.testing.expectEqualStrings("\x1b[0m", Style.reset.ansiCode());
}
