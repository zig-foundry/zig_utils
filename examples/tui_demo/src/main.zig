const std = @import("std");
const tui = @import("zig_utils").tui;

pub const panic = std.debug.FullPanic(restoreOnPanic);

fn restoreOnPanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    tui.endwin();
    std.debug.defaultPanic(msg, first_trace_addr);
}

pub fn main(init: std.process.Init) !void {
    const scr = try tui.initscr(init.gpa, init.io);
    defer scr.deinit();

    // Register color pairs (just like ncurses init_pair)
    scr.initPair(1, .cyan, .default);
    scr.initPair(2, .black, .cyan);
    scr.initPair(3, .yellow, .default);

    const items = [_][]const u8{
        "Terminal Raw Mode & Alternate Screen",
        "Double-Buffered Virtual/Physical Diffing",
        "ColorPair & SGR Attribute Engine",
        "Non-Blocking Poll & CSI Key Parser",
    };
    var selected: usize = 0;

    // 16ms poll timeout (~60 FPS)
    scr.stdscr.timeout(16);

    var running = true;
    while (running) {
        switch (try scr.stdscr.getch()) {
            .char => |c| if (c == 'q') {
                running = false;
            },
            .ctrl => |c| if (c == 'c') {
                running = false;
            },
            .up => if (selected > 0) {
                selected -= 1;
            },
            .down => if (selected + 1 < items.len) {
                selected += 1;
            },
            .resize => try scr.handleResize(),
            else => {},
        }

        // Draw outer border on stdscr
        scr.stdscr.erase();
        scr.stdscr.colorSet(1);
        scr.stdscr.attrOn(.{ .bold = true });
        scr.stdscr.box();
        scr.stdscr.mvPrint(2, 0, " zig_utils.tui ({d}x{d}) ", .{ scr.stdscr.width, scr.stdscr.height });
        scr.stdscr.attrOff(.{ .bold = true });

        // Create a child window inside stdscr
        if (scr.stdscr.width > 6 and scr.stdscr.height > 6) {
            var menu_win = try scr.newwin(2, 2, scr.stdscr.width - 4, scr.stdscr.height - 4);
            defer scr.delwin(&menu_win);

            menu_win.erase();
            menu_win.colorSet(3);
            menu_win.mvAddStr(1, 0, "Phase 1 Features (Up/Down to move, 'q' to quit):");

            for (items, 0..) |item, i| {
                const row: u16 = @intCast(i + 2);
                if (i == selected) {
                    menu_win.attrSet(.{ .bold = true }, 2);
                    menu_win.mvPrint(2, row, " > {s} ", .{item});
                } else {
                    menu_win.attrSet(.{}, 0);
                    menu_win.mvPrint(2, row, "   {s} ", .{item});
                }
            }

            // Stage both windows, then diff & flush once
            scr.stdscr.noutrefresh();
            menu_win.noutrefresh();
            try scr.doupdate();
        }
    }
}
