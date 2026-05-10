const std = @import("std");

pub const Command = union(enum) {
    exit,
    help: []const u8,
};

pub const compact_refcard =
    "Kiwi refcard\n" ++
    "      monad              dyad                  adverbs / notes\n" ++
    ":     identity           right/set             :x return  a:1 set\n" ++
    "+     flip               add                   f' each\n" ++
    "-     negate             subtract              f/ fold\n" ++
    "*     first              multiply              f\\ scan\n" ++
    "%     sqrt               divide                f': eachprior\n" ++
    "!     iota/key           dict/mod              f/: eachright\n" ++
    "&     where              min/and               f\\: eachleft\n" ++
    "|     reverse            max/or                x[y] index/apply\n" ++
    "< >   grade up/down      less/more             $[c;t;f] cond\n" ++
    "=     group              equal                 @[x;i;f;y] amend\n" ++
    "~     not                match                 .[x;i;f;y] deep amend\n" ++
    ",     enlist             concat\n" ++
    "^     null               fill/without\n" ++
    "#     count              take/reshape\n" ++
    "_     floor              drop\n" ++
    "$     string             cast\n" ++
    "?     ?i rng  ?X unique  X?y find  i?x rng\n" ++
    "@     type               apply\n" ++
    ".     value/eval         deep apply\n" ++
    "data:  1 2 3  2.5  1b  \"ab\"  `a  (1;2 3)  `a`b!1 2  +`a`b!(1 2;3 4)  {x+y}\n" ++
    "help:  load save sql register bytes utf8 char prng grad valuegrad\n" ++
    "meta:  \\ refcard  \\t:n expr time  \\\\ or \\q exit";

pub fn command(raw: []const u8) ?Command {
    const line = std.mem.trim(u8, raw, " \t\r\n");
    if (std.mem.eql(u8, line, "\\")) return .{ .help = compact_refcard };
    if (std.mem.eql(u8, line, "\\\\") or
        std.mem.eql(u8, line, "\\q") or
        std.mem.eql(u8, line, "quit") or
        std.mem.eql(u8, line, "exit"))
    {
        return .exit;
    }
    return null;
}

test "bare backslash returns compact refcard" {
    const cmd = command("\\") orelse return error.TestUnexpectedResult;
    switch (cmd) {
        .help => |text| {
            try std.testing.expect(std.mem.startsWith(u8, text, "Kiwi refcard"));
            try std.testing.expect(std.mem.indexOf(u8, text, "?i rng  ?X unique") != null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "only bare refcard and exit commands are classified" {
    try std.testing.expect(command("\\h") == null);
    try std.testing.expect(command("\\+") == null);
    try std.testing.expect(command("\\'") == null);
    try std.testing.expect(command("\\0") == null);
    try std.testing.expect(command("\\?") == null);
    try std.testing.expect(command("\\\\").? == .exit);
    try std.testing.expect(command("\\q").? == .exit);
}
