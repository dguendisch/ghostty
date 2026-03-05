const std = @import("std");

const Parser = @import("../../osc.zig").Parser;
const Command = @import("../../osc.zig").Command;

const log = std.log.scoped(.osc_rxvt_extension);

/// Parse OSC 777
pub fn parse(parser: *Parser, _: ?u8) ?*Command {
    const writer = parser.writer orelse {
        parser.state = .invalid;
        return null;
    };
    // ensure that we are sentinel terminated
    writer.writeByte(0) catch {
        parser.state = .invalid;
        return null;
    };
    const data = writer.buffered();
    const k = std.mem.indexOfScalar(u8, data, ';') orelse {
        parser.state = .invalid;
        return null;
    };
    const ext = data[0..k];
    if (std.mem.eql(u8, ext, "notify")) {
        const t = std.mem.indexOfScalarPos(u8, data, k + 1, ';') orelse {
            log.warn("rxvt notify extension is missing the title", .{});
            parser.state = .invalid;
            return null;
        };
        data[t] = 0;
        const title = data[k + 1 .. t :0];
        const body = data[t + 1 .. data.len - 1 :0];
        parser.command = .{
            .show_desktop_notification = .{
                .title = title,
                .body = body,
            },
        };
        return &parser.command;
    } else if (std.mem.eql(u8, ext, "statusbar")) {
        // OSC 777;statusbar;<json> - status bar content from shell integration
        const content = data[k + 1 .. data.len - 1 :0];
        parser.command = .{ .status_bar_content = content };
        return &parser.command;
    } else {
        log.warn("unknown rxvt extension: {s}", .{ext});
        parser.state = .invalid;
        return null;
    }
}

test "OSC: OSC 777 status bar content" {
    const testing = std.testing;

    var p: Parser = .init(null);

    const input = "777;statusbar;[{\"text\":\"hello\"}]";
    for (input) |ch| p.next(ch);

    const cmd = p.end('\x1b').?.*;
    try testing.expect(cmd == .status_bar_content);
    try testing.expectEqualStrings(cmd.status_bar_content, "[{\"text\":\"hello\"}]");
}

test "OSC: OSC 777 show desktop notification with title" {
    const testing = std.testing;

    var p: Parser = .init(null);

    const input = "777;notify;Title;Body";
    for (input) |ch| p.next(ch);

    const cmd = p.end('\x1b').?.*;
    try testing.expect(cmd == .show_desktop_notification);
    try testing.expectEqualStrings(cmd.show_desktop_notification.title, "Title");
    try testing.expectEqualStrings(cmd.show_desktop_notification.body, "Body");
}
