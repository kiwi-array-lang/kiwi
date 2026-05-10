const std = @import("std");
const bridge = @import("kiwi_bridge");

fn freeEvalOwned(result: *bridge.EvalOwned) void {
    if (result.text) |buf| {
        std.heap.c_allocator.free(buf);
        result.text = null;
    }
}

test "bridge evaluates simple expression" {
    const session = try bridge.kiwi_session.create(.cpu);
    defer session.destroy();

    var result = session.evalOwned("1+2");
    defer freeEvalOwned(&result);

    try std.testing.expectEqual(bridge.kiwi_status_e.ok, result.status);
    try std.testing.expect(result.echoed);
    try std.testing.expectEqual(bridge.kiwi_autograd_path_e.none, result.autograd_path);
    try std.testing.expectEqualStrings("3", result.text.?);
}

test "bridge keeps assignment state across evaluations" {
    const session = try bridge.kiwi_session.create(.cpu);
    defer session.destroy();

    var assign = session.evalOwned("a:1+2");
    defer freeEvalOwned(&assign);
    try std.testing.expectEqual(bridge.kiwi_status_e.ok, assign.status);
    try std.testing.expect(!assign.echoed);

    var use_value = session.evalOwned("a+4");
    defer freeEvalOwned(&use_value);
    try std.testing.expectEqual(bridge.kiwi_status_e.ok, use_value.status);
    try std.testing.expect(use_value.echoed);
    try std.testing.expectEqualStrings("7", use_value.text.?);
}

test "bridge maps parse errors" {
    const session = try bridge.kiwi_session.create(.cpu);
    defer session.destroy();

    var result = session.evalOwned(")");
    defer freeEvalOwned(&result);

    try std.testing.expectEqual(bridge.kiwi_status_e.parse, result.status);
    try std.testing.expect(!result.echoed);
    try std.testing.expectEqual(@as(?[]u8, null), result.text);
}

test "bridge returns the current main-runtime autograd metadata for gradients" {
    const session = try bridge.kiwi_session.create(.cpu);
    defer session.destroy();

    var result = session.evalOwned("grad[{x*x}][3]");
    defer freeEvalOwned(&result);

    try std.testing.expectEqual(bridge.kiwi_status_e.ok, result.status);
    try std.testing.expect(result.echoed);
    try std.testing.expectEqualStrings("6", result.text.?);
    try std.testing.expectEqual(bridge.kiwi_autograd_path_e.none, result.autograd_path);
}
