const std = @import("std");

pub const Command = union(enum) {
    exit,
    help: []const u8,
};

pub const compact_refcard =
    "verb  monad       dyad\n" ++
    "----  ----------- ------------\n" ++
    ":     identity    right,set\n" ++
    "+     flip        add\n" ++
    "-     negate      subtract\n" ++
    "*     first       multiply\n" ++
    "%     sqrt        divide\n" ++
    "!     iota,key    dict,mod\n" ++
    "&     where       min,and\n" ++
    "|     reverse     max,or\n" ++
    "<     grade up    less\n" ++
    ">     grade down  more\n" ++
    "=     group       equal\n" ++
    "~     not         match\n" ++
    ",     enlist      concat\n" ++
    "^     null        fill,without\n" ++
    "#     count       take,reshape\n" ++
    "_     floor       drop\n" ++
    "$     string      cast\n" ++
    "?     rng,unique  find,rng\n" ++
    "@     type        apply\n" ++
    ".     value,eval  deep apply\n" ++
    "\n" ++
    "adverbs:\n" ++
    "f'    each\n" ++
    "f/    fold\n" ++
    "f\\    scan\n" ++
    "f':   eachprior\n" ++
    "f/:   eachright\n" ++
    "f\\:   eachleft\n" ++
    "\n" ++
    "forms:\n" ++
    ":x return\n" ++
    "a:1 set\n" ++
    "x[y] index/apply\n" ++
    "$[c;t;f] cond\n" ++
    "@[x;i;f;y] amend\n" ++
    ".[x;i;f;y] deep amend\n" ++
    "\n" ++
    "data literals:\n" ++
    "type    scalar  vector\n" ++
    "int     1       1 2 3\n" ++
    "float   2.5     2.5 3.5\n" ++
    "bool    1b      101b\n" ++
    "char    \"a\"     \"ab\"\n" ++
    "symbol  `a      `a`b\n" ++
    "list            (1;2 3)\n" ++
    "dict            `a`b!1 2\n" ++
    "table           +`a`b!(1 2;3 4)\n" ++
    "fn              {x+y}\n" ++
    "\n" ++
    "text:\n" ++
    "sep\\src split\n" ++
    "sep/xs join\n" ++
    "1<#needle\\src contains\n" ++
    "\",\"\\\"a,b,c\"\n" ++
    "\",\"/(\"a\";\"b\")\n" ++
    "1<#\",\"\\\"a,b\"\n" ++
    "\n" ++
    "cast:\n" ++
    "`c$65 -> \"A\"\n" ++
    "`i$\"ab\" -> 97 98\n" ++
    "`I$\"23\" -> 23\n" ++
    "\n" ++
    "built-in verbs:\n" ++
    "load save sql register\n" ++
    "grad valuegrad\n" ++
    "\n" ++
    "mlx:\n" ++
    "rotcache rotcacheupdate\n" ++
    "rotcacheview rope ropeflat\n" ++
    "ropecisflat rmsnorm layernorm\n" ++
    "gelu geluapprox mlpdense\n" ++
    "conv2d convtranspose2d\n" ++
    "upsamplenearest2d groupnorm\n" ++
    "softmax sdpa sam3boxrpb\n" ++
    "sdpamask sdpaflat\n" ++
    "\n" ++
    "meta:\n" ++
    "\\ refcard\n" ++
    "\\t:n expr time\n" ++
    "\\\\ exit";

pub fn command(raw: []const u8) ?Command {
    const line = std.mem.trim(u8, raw, " \t\r\n");
    if (std.mem.eql(u8, line, "\\")) return .{ .help = compact_refcard };
    if (std.mem.eql(u8, line, "\\\\")) return .exit;
    return null;
}

test "bare backslash returns compact refcard" {
    const cmd = command("\\") orelse return error.TestUnexpectedResult;
    switch (cmd) {
        .help => |text| {
            try std.testing.expect(std.mem.startsWith(u8, text, "verb  monad       dyad"));
            try std.testing.expect(std.mem.indexOf(u8, text, "verb  monad       dyad") != null);
            try std.testing.expect(std.mem.indexOf(u8, text, "?     rng,unique  find,rng") != null);
            try std.testing.expect(std.mem.indexOf(u8, text, "mlx:\n") != null);
            try std.testing.expect(std.mem.indexOf(u8, text, "rotcache rotcacheupdate") != null);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "only bare refcard and double-backslash exit commands are classified" {
    try std.testing.expect(command("\\h") == null);
    try std.testing.expect(command("\\+") == null);
    try std.testing.expect(command("\\'") == null);
    try std.testing.expect(command("\\0") == null);
    try std.testing.expect(command("\\?") == null);
    try std.testing.expect(command("\\\\").? == .exit);
    try std.testing.expect(command("\\q") == null);
    try std.testing.expect(command("quit") == null);
    try std.testing.expect(command("exit") == null);
}

test "compact refcard stays within narrow display width" {
    var line_iter = std.mem.splitScalar(u8, compact_refcard, '\n');
    while (line_iter.next()) |line| {
        try std.testing.expect(line.len <= 36);
    }
}
