const std = @import("std");

pub const TokenKind = enum(c_int) {
    plain = 0,
    number = 1,
    string = 2,
    symbol = 3,
    identifier = 4,
    builtin = 5,
    adverb = 6,
    comment = 7,
    punctuation = 8,
};

pub const Token = extern struct {
    kind: TokenKind,
    start: usize,
    end: usize,
};

pub const TokenBuffer = struct {
    tokens: []Token,
    len: usize = 0,
    total: usize = 0,

    pub fn emit(self: *TokenBuffer, kind: TokenKind, start: usize, end: usize) void {
        if (end <= start) return;
        if (self.len < self.tokens.len) {
            self.tokens[self.len] = .{
                .kind = kind,
                .start = start,
                .end = end,
            };
            self.len += 1;
        }
        self.total += 1;
    }
};

pub fn tokenize(source: []const u8, buffer: *TokenBuffer) void {
    var line_start: usize = 0;
    var index: usize = 0;
    while (index < source.len) {
        const start = index;
        const ch = source[index];

        if (ch == '\n') {
            index += 1;
            line_start = index;
            buffer.emit(.plain, start, index);
            continue;
        }

        if (isHorizontalWhitespace(ch)) {
            index += 1;
            while (index < source.len and isHorizontalWhitespace(source[index])) : (index += 1) {}
            buffer.emit(.plain, start, index);
            continue;
        }

        if (startsComment(source, index, line_start)) {
            index = scanLineEnd(source, index);
            buffer.emit(.comment, start, index);
            continue;
        }

        if (ch == '"') {
            index = scanString(source, index);
            buffer.emit(.string, start, index);
            continue;
        }

        if (ch == '`') {
            index = scanSymbol(source, index);
            buffer.emit(.symbol, start, index);
            continue;
        }

        if (startsNumber(source, index, line_start)) {
            if (scanNumber(source, index)) |end| {
                index = end;
                buffer.emit(.number, start, index);
                continue;
            }
        }

        if (isIdentStart(ch)) {
            index += 1;
            while (index < source.len and isIdentContinue(source[index])) : (index += 1) {}
            buffer.emit(.identifier, start, index);
            continue;
        }

        if (isAdverbStart(ch)) {
            index += 1;
            if (index < source.len and source[index] == ':') index += 1;
            buffer.emit(.adverb, start, index);
            continue;
        }

        if (isBuiltin(ch)) {
            index += 1;
            buffer.emit(.builtin, start, index);
            continue;
        }

        if (isPunctuation(ch)) {
            index += 1;
            buffer.emit(.punctuation, start, index);
            continue;
        }

        if (ch >= 0x80) {
            index += 1;
            while (index < source.len and source[index] >= 0x80) : (index += 1) {}
            buffer.emit(.identifier, start, index);
            continue;
        }

        index += 1;
        buffer.emit(.plain, start, index);
    }
}

pub fn count(source: []const u8) usize {
    var empty: [0]Token = .{};
    var buffer = TokenBuffer{ .tokens = empty[0..] };
    tokenize(source, &buffer);
    return buffer.total;
}

fn isHorizontalWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r';
}

fn isLineStartOrAfterWhitespace(source: []const u8, index: usize, line_start: usize) bool {
    if (index == line_start) return true;
    return index > 0 and std.ascii.isWhitespace(source[index - 1]);
}

fn startsComment(source: []const u8, index: usize, line_start: usize) bool {
    return source[index] == '/' and isLineStartOrAfterWhitespace(source, index, line_start);
}

fn scanLineEnd(source: []const u8, start: usize) usize {
    var index = start;
    while (index < source.len and source[index] != '\n') : (index += 1) {}
    return index;
}

fn scanString(source: []const u8, start: usize) usize {
    var index = start + 1;
    while (index < source.len and source[index] != '"' and source[index] != '\n') : (index += 1) {}
    if (index < source.len and source[index] == '"') index += 1;
    return index;
}

fn scanSymbol(source: []const u8, start: usize) usize {
    var index = start + 1;
    while (index < source.len and isIdentContinue(source[index])) : (index += 1) {}
    return index;
}

fn startsNumber(source: []const u8, index: usize, line_start: usize) bool {
    const ch = source[index];
    if (std.ascii.isDigit(ch)) return true;
    if (ch != '-' or index + 1 >= source.len or !std.ascii.isDigit(source[index + 1])) return false;
    if (index == line_start) return true;
    const previous = source[index - 1];
    return std.ascii.isWhitespace(previous) or isBuiltin(previous) or isAdverbStart(previous) or isOpeningPunctuation(previous);
}

fn scanNumber(source: []const u8, start: usize) ?usize {
    var index = start;
    const signed = source[index] == '-';
    if (signed) index += 1;
    if (index >= source.len or !std.ascii.isDigit(source[index])) return null;

    if (!signed and index + 1 < source.len and source[index] == '0' and source[index + 1] == 'x') {
        index += 2;
        while (index < source.len and std.ascii.isAlphanumeric(source[index])) : (index += 1) {}
        return index;
    }

    const digits_start = index;
    while (index < source.len and std.ascii.isDigit(source[index])) : (index += 1) {}
    const digit_count = index - digits_start;

    if (digit_count == 1 and source[digits_start] == '0' and index < source.len) {
        switch (source[index]) {
            'N' => return index + 1,
            'n', 'w' => return if (index + 1 < source.len and source[index + 1] == 'e') index + 2 else index + 1,
            else => {},
        }
    }

    if (index < source.len and source[index] == 'b') {
        if (isBoolDigitRun(source[digits_start..index])) return index + 1;
        return index;
    }

    if (index < source.len and source[index] == '.') {
        const fraction_start = index + 1;
        index = fraction_start;
        while (index < source.len and std.ascii.isDigit(source[index])) : (index += 1) {}
    }

    if (index < source.len and (source[index] == 'e' or source[index] == 'E')) {
        var exponent_index = index + 1;
        if (exponent_index < source.len and (source[exponent_index] == '-' or source[exponent_index] == '+')) exponent_index += 1;
        const exponent_digits = exponent_index;
        while (exponent_index < source.len and std.ascii.isDigit(source[exponent_index])) : (exponent_index += 1) {}
        if (exponent_index != exponent_digits) index = exponent_index;
    }

    if (index < source.len and (source[index] == 'f' or source[index] == 'e')) index += 1;
    return index;
}

fn isIdentStart(ch: u8) bool {
    return std.ascii.isAlphabetic(ch) or ch == '_';
}

fn isBoolDigitRun(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |ch| {
        if (ch != '0' and ch != '1') return false;
    }
    return true;
}

fn isIdentContinue(ch: u8) bool {
    return isIdentStart(ch) or std.ascii.isDigit(ch);
}

fn isAdverbStart(ch: u8) bool {
    return ch == '/' or ch == '\\' or ch == '\'';
}

fn isBuiltin(ch: u8) bool {
    return switch (ch) {
        ':', '+', '-', '*', '%', '!', '&', '|', '<', '>', '~', ',', '#', '_', '^', '=', '$', '?' => true,
        else => false,
    };
}

fn isOpeningPunctuation(ch: u8) bool {
    return ch == '(' or ch == '[' or ch == '{' or ch == ';';
}

fn isPunctuation(ch: u8) bool {
    return switch (ch) {
        '(', ')', '[', ']', '{', '}', ';', '.', '@' => true,
        else => false,
    };
}

test "tokenizes core kiwi syntax" {
    const source = "x:0N 0n 1b -2 3.5f +/x / comment";
    var tokens: [32]Token = undefined;
    var buffer = TokenBuffer{ .tokens = tokens[0..] };
    tokenize(source, &buffer);

    try std.testing.expectEqual(@as(usize, 17), buffer.total);
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqualStrings("x", source[tokens[0].start..tokens[0].end]);
    try std.testing.expectEqual(TokenKind.builtin, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.number, tokens[2].kind);
    try std.testing.expectEqualStrings("0N", source[tokens[2].start..tokens[2].end]);
    try std.testing.expectEqual(TokenKind.number, tokens[4].kind);
    try std.testing.expectEqualStrings("0n", source[tokens[4].start..tokens[4].end]);
    try std.testing.expectEqual(TokenKind.number, tokens[6].kind);
    try std.testing.expectEqualStrings("1b", source[tokens[6].start..tokens[6].end]);
    try std.testing.expectEqual(TokenKind.number, tokens[8].kind);
    try std.testing.expectEqualStrings("-2", source[tokens[8].start..tokens[8].end]);
    try std.testing.expectEqual(TokenKind.number, tokens[10].kind);
    try std.testing.expectEqualStrings("3.5f", source[tokens[10].start..tokens[10].end]);
    try std.testing.expectEqual(TokenKind.builtin, tokens[12].kind);
    try std.testing.expectEqual(TokenKind.adverb, tokens[13].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[14].kind);
    try std.testing.expectEqual(TokenKind.comment, tokens[16].kind);
    try std.testing.expectEqualStrings("/ comment", source[tokens[16].start..tokens[16].end]);
}

test "does not treat fold slash as comment" {
    const source = "+/1 2 3\n1 2 / comment";
    var tokens: [16]Token = undefined;
    var buffer = TokenBuffer{ .tokens = tokens[0..] };
    tokenize(source, &buffer);

    try std.testing.expectEqual(TokenKind.builtin, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.adverb, tokens[1].kind);
    try std.testing.expectEqualStrings("/", source[tokens[1].start..tokens[1].end]);
    try std.testing.expectEqual(TokenKind.comment, tokens[12].kind);
}

test "tokenizes boolean vector literal as one number token" {
    const source = "mask:101001b";
    var tokens: [8]Token = undefined;
    var buffer = TokenBuffer{ .tokens = tokens[0..] };
    tokenize(source, &buffer);

    try std.testing.expectEqual(TokenKind.number, tokens[2].kind);
    try std.testing.expectEqualStrings("101001b", source[tokens[2].start..tokens[2].end]);
}
