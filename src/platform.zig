const builtin = @import("builtin");
const std = @import("std");

const host_has_posix = builtin.os.tag != .freestanding and builtin.os.tag != .wasi;
pub const Fd = if (host_has_posix) std.posix.fd_t else i32;
const ProcessFd = if (host_has_posix) std.c.fd_t else i32;
const ProcessPid = if (host_has_posix) std.c.pid_t else i32;

pub const FileHandle = struct {
    fd: Fd,

    pub fn close(self: FileHandle) void {
        if (comptime !host_has_posix) return;
        _ = std.c.close(self.fd);
    }

    pub fn read(self: FileHandle, buffer: []u8) !usize {
        if (comptime !host_has_posix) return error.UnsupportedTarget;
        return try std.posix.read(self.fd, buffer);
    }

    pub fn readAll(self: FileHandle, buffer: []u8) !usize {
        var total: usize = 0;
        while (total < buffer.len) {
            const n = try self.read(buffer[total..]);
            if (n == 0) break;
            total += n;
        }
        return total;
    }

    pub fn writeAll(self: FileHandle, bytes: []const u8) !void {
        try writeFdAll(self.fd, bytes);
    }

    pub fn readChunkAlloc(self: FileHandle, allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
        return try readFdChunkAlloc(allocator, self.fd, max_bytes);
    }

    pub fn readUntilByteAlloc(self: FileHandle, allocator: std.mem.Allocator, delimiter: u8, max_bytes: usize) ![]u8 {
        return try readFdUntilByteAlloc(allocator, self.fd, delimiter, max_bytes);
    }

    pub fn flush(self: FileHandle) !void {
        _ = self;
    }

    pub fn size(self: FileHandle) !u64 {
        if (comptime !host_has_posix) return error.UnsupportedTarget;
        const current = std.c.lseek(self.fd, 0, std.c.SEEK.CUR);
        if (current < 0) return error.InputOutput;
        const end = std.c.lseek(self.fd, 0, std.c.SEEK.END);
        if (end < 0) return error.InputOutput;
        if (std.c.lseek(self.fd, current, std.c.SEEK.SET) < 0) return error.InputOutput;
        return @intCast(end);
    }

    pub fn stat(self: FileHandle) !FileStat {
        return try statFd(self.fd);
    }
};

pub const TcpHandle = struct {
    fd: Fd,

    pub fn close(self: TcpHandle) void {
        if (comptime !host_has_posix) return;
        _ = std.c.close(self.fd);
    }

    pub fn read(self: TcpHandle, buffer: []u8) !usize {
        if (comptime !host_has_posix) return error.UnsupportedTarget;
        return try std.posix.read(self.fd, buffer);
    }

    pub fn writeAll(self: TcpHandle, bytes: []const u8) !void {
        try writeFdAll(self.fd, bytes);
    }

    pub fn readChunkAlloc(self: TcpHandle, allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
        return try readFdChunkAlloc(allocator, self.fd, max_bytes);
    }

    pub fn readUntilByteAlloc(self: TcpHandle, allocator: std.mem.Allocator, delimiter: u8, max_bytes: usize) ![]u8 {
        return try readFdUntilByteAlloc(allocator, self.fd, delimiter, max_bytes);
    }

    pub fn flush(self: TcpHandle) !void {
        _ = self;
    }
};

pub const FileStatKind = enum {
    file,
    dir,
    symlink,
    pipe,
    socket,
    char,
    block,
    other,
};

pub const FileStat = struct {
    kind: FileStatKind,
    size: u64,
    mtime_ns: i64,
};

pub const ProcessHandle = struct {
    pid: ?ProcessPid,
    stdin_fd: ProcessFd,
    stdout_fd: ProcessFd,

    pub fn stdinOpen(self: *const ProcessHandle) bool {
        return self.stdin_fd >= 0;
    }

    pub fn stdoutOpen(self: *const ProcessHandle) bool {
        return self.stdout_fd >= 0;
    }

    pub fn closeStdin(self: *ProcessHandle) void {
        closeFd(&self.stdin_fd);
    }

    pub fn closeStdout(self: *ProcessHandle) void {
        closeFd(&self.stdout_fd);
    }

    pub fn writeAll(self: *ProcessHandle, bytes: []const u8) !void {
        if (!self.stdinOpen()) return error.ProcessStdinClosed;
        try writeFdAll(self.stdin_fd, bytes);
    }

    pub fn readStdoutAlloc(self: *ProcessHandle, allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
        self.closeStdin();
        if (!self.stdoutOpen()) return error.ProcessStdoutClosed;
        const stdout = readFdAlloc(allocator, self.stdout_fd, max_bytes) catch |err| {
            self.closeStdout();
            self.wait() catch {};
            return err;
        };
        errdefer allocator.free(stdout);
        self.closeStdout();
        try self.wait();
        return stdout;
    }

    pub fn readStdoutChunkAlloc(self: *ProcessHandle, allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
        self.closeStdin();
        if (!self.stdoutOpen()) return error.ProcessStdoutClosed;
        const stdout = readFdChunkAlloc(allocator, self.stdout_fd, max_bytes) catch |err| {
            self.closeStdout();
            self.wait() catch {};
            return err;
        };
        errdefer allocator.free(stdout);
        if (stdout.len == 0) {
            self.closeStdout();
            try self.wait();
        }
        return stdout;
    }

    pub fn readStdoutUntilByteAlloc(self: *ProcessHandle, allocator: std.mem.Allocator, delimiter: u8, max_bytes: usize) ![]u8 {
        self.closeStdin();
        if (!self.stdoutOpen()) return error.ProcessStdoutClosed;
        const stdout = readFdUntilByteAlloc(allocator, self.stdout_fd, delimiter, max_bytes) catch |err| {
            self.closeStdout();
            self.wait() catch {};
            return err;
        };
        errdefer allocator.free(stdout);
        if (stdout.len == 0 or stdout[stdout.len - 1] != delimiter) {
            self.closeStdout();
            try self.wait();
        }
        return stdout;
    }

    pub fn close(self: *ProcessHandle) !void {
        self.closeStdin();
        self.closeStdout();
        try self.wait();
    }

    pub fn deinit(self: *ProcessHandle) void {
        self.close() catch {};
    }

    fn wait(self: *ProcessHandle) !void {
        const pid = self.pid orelse return;
        self.pid = null;
        try waitProcess(pid);
    }
};

pub const FdWriter = struct {
    fd: Fd,

    pub fn writeAll(self: *const FdWriter, bytes: []const u8) !void {
        try writeFdAll(self.fd, bytes);
    }

    pub fn writeByte(self: *const FdWriter, byte: u8) !void {
        try self.writeAll(&.{byte});
    }

    pub fn print(self: *const FdWriter, comptime fmt: []const u8, args: anytype) !void {
        var stack_buf: [4096]u8 = undefined;
        const text = std.fmt.bufPrint(&stack_buf, fmt, args) catch {
            const allocated = std.fmt.allocPrint(std.heap.page_allocator, fmt, args) catch return error.WriteFailed;
            defer std.heap.page_allocator.free(allocated);
            try self.writeAll(allocated);
            return;
        };
        try self.writeAll(text);
    }
};

pub fn stdoutWriter() FdWriter {
    return .{ .fd = if (comptime host_has_posix) std.posix.STDOUT_FILENO else -1 };
}

pub fn stderrWriter() FdWriter {
    return .{ .fd = if (comptime host_has_posix) std.posix.STDERR_FILENO else -1 };
}

pub fn stdinFile() FileHandle {
    return .{ .fd = if (comptime host_has_posix) std.posix.STDIN_FILENO else -1 };
}

pub fn stdoutFile() FileHandle {
    return .{ .fd = if (comptime host_has_posix) std.posix.STDOUT_FILENO else -1 };
}

pub fn stderrFile() FileHandle {
    return .{ .fd = if (comptime host_has_posix) std.posix.STDERR_FILENO else -1 };
}

pub fn isStdinTty() bool {
    if (comptime !host_has_posix or builtin.os.tag == .windows) return false;
    return std.c.isatty(std.posix.STDIN_FILENO) == 1;
}

pub fn isStdoutTty() bool {
    if (comptime !host_has_posix or builtin.os.tag == .windows) return false;
    return std.c.isatty(std.posix.STDOUT_FILENO) == 1;
}

pub fn openFileRead(path: []const u8) !FileHandle {
    if (comptime !host_has_posix) return error.UnsupportedTarget;
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0);
    return .{ .fd = fd };
}

pub fn openFileWrite(path: []const u8) !FileHandle {
    if (comptime !host_has_posix) return error.UnsupportedTarget;
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o666);
    return .{ .fd = fd };
}

pub fn openFileAppend(path: []const u8) !FileHandle {
    if (comptime !host_has_posix) return error.UnsupportedTarget;
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true }, 0o666);
    return .{ .fd = fd };
}

const PosixIpAddress = extern union {
    any: std.posix.sockaddr,
    in: std.posix.sockaddr.in,
    in6: std.posix.sockaddr.in6,
};

fn tcpAddressFamily(address: *const std.Io.net.IpAddress) std.posix.sa_family_t {
    return switch (address.*) {
        .ip4 => std.posix.AF.INET,
        .ip6 => std.posix.AF.INET6,
    };
}

fn tcpAddressToPosix(address: *const std.Io.net.IpAddress, storage: *PosixIpAddress) std.posix.socklen_t {
    return switch (address.*) {
        .ip4 => |ip4| {
            storage.in = .{
                .port = std.mem.nativeToBig(u16, ip4.port),
                .addr = @bitCast(ip4.bytes),
            };
            return @sizeOf(std.posix.sockaddr.in);
        },
        .ip6 => |ip6| {
            storage.in6 = .{
                .port = std.mem.nativeToBig(u16, ip6.port),
                .flowinfo = ip6.flow,
                .addr = ip6.bytes,
                .scope_id = ip6.interface.index,
            };
            return @sizeOf(std.posix.sockaddr.in6);
        },
    };
}

fn openTcpSocket(family: std.posix.sa_family_t) !Fd {
    if (comptime !host_has_posix) return error.UnsupportedTarget;
    while (true) {
        const rc = std.posix.system.socket(
            @as(c_uint, @intCast(family)),
            @as(c_uint, @intCast(std.posix.SOCK.STREAM)),
            @as(c_uint, @intCast(std.posix.IPPROTO.TCP)),
        );
        switch (std.posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            .AFNOSUPPORT => return error.AddressFamilyUnsupported,
            .MFILE => return error.ProcessFdQuotaExceeded,
            .NFILE => return error.SystemFdQuotaExceeded,
            .NOBUFS, .NOMEM => return error.SystemResources,
            .PROTONOSUPPORT => return error.ProtocolUnsupportedByAddressFamily,
            .PROTOTYPE => return error.SocketModeUnsupported,
            else => return error.InputOutput,
        }
    }
}

fn connectTcpFd(fd: std.posix.fd_t, address: *const std.posix.sockaddr, address_len: std.posix.socklen_t) !void {
    while (true) {
        switch (std.posix.errno(std.posix.system.connect(fd, address, address_len))) {
            .SUCCESS => return,
            .INTR => continue,
            .ADDRNOTAVAIL => return error.AddressUnavailable,
            .AFNOSUPPORT => return error.AddressFamilyUnsupported,
            .AGAIN, .INPROGRESS => return error.WouldBlock,
            .ALREADY => return error.ConnectionPending,
            .CONNREFUSED => return error.ConnectionRefused,
            .CONNRESET => return error.ConnectionResetByPeer,
            .HOSTUNREACH => return error.HostUnreachable,
            .NETUNREACH => return error.NetworkUnreachable,
            .TIMEDOUT => return error.Timeout,
            .ACCES, .PERM => return error.AccessDenied,
            .NETDOWN => return error.NetworkDown,
            else => return error.InputOutput,
        }
    }
}

pub fn connectTcp(address_text: []const u8) !TcpHandle {
    if (comptime !host_has_posix or builtin.os.tag == .windows) return error.UnsupportedTarget;

    const address = std.Io.net.IpAddress.parseLiteral(address_text) catch return error.InvalidAddress;
    const fd = try openTcpSocket(tcpAddressFamily(&address));
    errdefer _ = std.c.close(fd);

    var storage: PosixIpAddress = undefined;
    const address_len = tcpAddressToPosix(&address, &storage);
    try connectTcpFd(fd, &storage.any, address_len);
    return .{ .fd = fd };
}

fn closeFd(fd: *ProcessFd) void {
    if (comptime !host_has_posix) {
        fd.* = -1;
        return;
    }
    if (fd.* < 0) return;
    _ = std.c.close(fd.*);
    fd.* = -1;
}

fn statKind(mode: u32) FileStatKind {
    if (std.c.S.ISREG(mode)) return .file;
    if (std.c.S.ISDIR(mode)) return .dir;
    if (std.c.S.ISLNK(mode)) return .symlink;
    if (std.c.S.ISFIFO(mode)) return .pipe;
    if (std.c.S.ISSOCK(mode)) return .socket;
    if (std.c.S.ISCHR(mode)) return .char;
    if (std.c.S.ISBLK(mode)) return .block;
    return .other;
}

fn timespecNs(ts: std.c.timespec) !i64 {
    const ns = @as(i128, ts.sec) * std.time.ns_per_s + @as(i128, ts.nsec);
    return std.math.cast(i64, ns) orelse error.UnsupportedTimestamp;
}

fn fileStatFromC(st: std.c.Stat) !FileStat {
    if (st.size < 0) return error.UnsupportedFileSize;
    return .{
        .kind = statKind(@intCast(st.mode)),
        .size = @intCast(st.size),
        .mtime_ns = try timespecNs(st.mtime()),
    };
}

fn linuxTimestampNs(ts: std.os.linux.statx_timestamp) !i64 {
    const ns = @as(i128, ts.sec) * std.time.ns_per_s + @as(i128, ts.nsec);
    return std.math.cast(i64, ns) orelse error.UnsupportedTimestamp;
}

fn fileStatFromLinux(st: std.os.linux.Statx) !FileStat {
    if (!st.mask.TYPE or !st.mask.SIZE or !st.mask.MTIME) return error.InputOutput;
    return .{
        .kind = statKind(@intCast(st.mode)),
        .size = st.size,
        .mtime_ns = try linuxTimestampNs(st.mtime),
    };
}

fn statFdLinux(fd: Fd) !FileStat {
    var st = std.mem.zeroes(std.os.linux.Statx);
    while (true) {
        switch (std.os.linux.errno(std.os.linux.statx(
            fd,
            "",
            std.os.linux.AT.EMPTY_PATH,
            .{ .TYPE = true, .SIZE = true, .MTIME = true },
            &st,
        ))) {
            .SUCCESS => return try fileStatFromLinux(st),
            .INTR => continue,
            else => return error.InputOutput,
        }
    }
}

fn statPathLinux(path_z: [:0]const u8) !FileStat {
    var st = std.mem.zeroes(std.os.linux.Statx);
    while (true) {
        switch (std.os.linux.errno(std.os.linux.statx(
            std.os.linux.AT.FDCWD,
            path_z.ptr,
            0,
            .{ .TYPE = true, .SIZE = true, .MTIME = true },
            &st,
        ))) {
            .SUCCESS => return try fileStatFromLinux(st),
            .INTR => continue,
            .NOENT, .NOTDIR => return error.FileNotFound,
            else => return error.InputOutput,
        }
    }
}

pub fn statFd(fd: Fd) !FileStat {
    if (comptime !host_has_posix or builtin.os.tag == .windows) return error.UnsupportedTarget;
    if (comptime builtin.os.tag == .linux) return try statFdLinux(fd);
    var st: std.c.Stat = undefined;
    while (true) {
        switch (std.posix.errno(std.c.fstat(fd, &st))) {
            .SUCCESS => return try fileStatFromC(st),
            .INTR => continue,
            else => return error.InputOutput,
        }
    }
}

pub fn statPath(allocator: std.mem.Allocator, path: []const u8) !FileStat {
    if (comptime !host_has_posix or builtin.os.tag == .windows) return error.UnsupportedTarget;
    const path_z = try allocator.dupeSentinel(u8, path, 0);
    defer allocator.free(path_z);
    if (comptime builtin.os.tag == .linux) return try statPathLinux(path_z);
    var st: std.c.Stat = undefined;
    while (true) {
        switch (std.posix.errno(std.c.fstatat(std.posix.AT.FDCWD, path_z.ptr, &st, 0))) {
            .SUCCESS => return try fileStatFromC(st),
            .INTR => continue,
            .NOENT, .NOTDIR => return error.FileNotFound,
            else => return error.InputOutput,
        }
    }
}

pub fn readFdAlloc(allocator: std.mem.Allocator, fd: Fd, max_bytes: usize) ![]u8 {
    if (comptime !host_has_posix) return error.UnsupportedTarget;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var buffer: [4096]u8 = undefined;
    while (true) {
        const n = try std.posix.read(fd, &buffer);
        if (n == 0) break;
        if (out.items.len + n > max_bytes) return error.StreamTooLong;
        try out.appendSlice(allocator, buffer[0..n]);
    }
    return try out.toOwnedSlice(allocator);
}

pub fn readFdChunkAlloc(allocator: std.mem.Allocator, fd: Fd, max_bytes: usize) ![]u8 {
    if (comptime !host_has_posix) return error.UnsupportedTarget;
    if (max_bytes == 0) return try allocator.dupe(u8, &.{});
    const out = try allocator.alloc(u8, max_bytes);
    errdefer allocator.free(out);
    const n = try std.posix.read(fd, out);
    return try allocator.realloc(out, n);
}

pub fn readFdUntilByteAlloc(allocator: std.mem.Allocator, fd: Fd, delimiter: u8, max_bytes: usize) ![]u8 {
    if (comptime !host_has_posix) return error.UnsupportedTarget;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var byte: [1]u8 = undefined;
    while (true) {
        const n = try std.posix.read(fd, &byte);
        if (n == 0) break;
        if (out.items.len + 1 > max_bytes) return error.StreamTooLong;
        try out.append(allocator, byte[0]);
        if (byte[0] == delimiter) break;
    }
    return try out.toOwnedSlice(allocator);
}

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    const file = try openFileRead(path);
    defer file.close();
    return try readFdAlloc(allocator, file.fd, max_bytes);
}

pub fn readStdinAlloc(allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
    return try readFdAlloc(allocator, if (comptime host_has_posix) std.posix.STDIN_FILENO else -1, max_bytes);
}

const ProcessStdinWriter = struct {
    fd: Fd,
    bytes: []const u8,
    err: ?anyerror = null,
};

const ProcessArgv = struct {
    storage: [:null]?[*:0]const u8,
    strings: [][:0]u8,
};

fn writeProcessStdin(writer: *ProcessStdinWriter) void {
    if (comptime !host_has_posix) {
        writer.err = error.UnsupportedTarget;
        return;
    }
    defer _ = std.c.close(writer.fd);
    writeFdAll(writer.fd, writer.bytes) catch |err| {
        writer.err = err;
    };
}

fn waitProcess(pid: ProcessPid) !void {
    if (comptime !host_has_posix) return error.UnsupportedTarget;
    var status: c_int = 0;
    while (true) {
        const rc = std.c.waitpid(pid, &status, 0);
        switch (std.posix.errno(rc)) {
            .SUCCESS => break,
            .INTR => continue,
            else => return error.ProcessWaitFailed,
        }
    }

    if ((status & 0x7f) != 0 or ((status >> 8) & 0xff) != 0) return error.ProcessFailed;
}

fn execCommand(argv: [*:null]const ?[*:0]const u8) noreturn {
    const file = argv[0] orelse std.c._exit(127);
    const file_bytes = std.mem.span(file);
    if (std.mem.indexOfScalar(u8, file_bytes, '/') != null) {
        _ = std.c.execve(file, argv, std.c.environ);
        std.c._exit(127);
    }

    const path_bytes = if (std.c.getenv("PATH")) |path| std.mem.span(path) else "/usr/local/bin:/usr/bin:/bin";
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    var it = std.mem.tokenizeScalar(u8, path_bytes, ':');
    while (it.next()) |dir| {
        const len = dir.len + 1 + file_bytes.len;
        if (len >= path_buf.len) continue;
        @memcpy(path_buf[0..dir.len], dir);
        path_buf[dir.len] = '/';
        @memcpy(path_buf[dir.len + 1 ..][0..file_bytes.len], file_bytes);
        path_buf[len] = 0;
        _ = std.c.execve(path_buf[0..len :0].ptr, argv, std.c.environ);
    }
    std.c._exit(127);
}

fn allocProcessArgv(allocator: std.mem.Allocator, argv: []const []const u8) !ProcessArgv {
    if (argv.len == 0) return error.InvalidArgument;
    const storage = try allocator.allocSentinel(?[*:0]const u8, argv.len, null);
    errdefer allocator.free(storage);
    const strings = try allocator.alloc([:0]u8, argv.len);
    errdefer allocator.free(strings);

    var initialized: usize = 0;
    errdefer {
        for (strings[0..initialized]) |arg| allocator.free(arg);
    }
    for (argv, 0..) |arg, idx| {
        if (arg.len == 0 or std.mem.indexOfScalar(u8, arg, 0) != null) return error.InvalidArgument;
        const owned = try allocator.dupeSentinel(u8, arg, 0);
        strings[idx] = owned;
        initialized += 1;
        storage[idx] = owned.ptr;
    }
    return .{ .storage = storage, .strings = strings };
}

pub fn freeProcessArgv(allocator: std.mem.Allocator, argv: ProcessArgv) void {
    for (argv.strings) |arg| allocator.free(arg);
    allocator.free(argv.strings);
    allocator.free(argv.storage);
}

pub fn spawnProcess(allocator: std.mem.Allocator, argv: []const []const u8) !ProcessHandle {
    if (comptime builtin.os.tag == .wasi or builtin.os.tag == .freestanding or builtin.os.tag == .windows) return error.UnsupportedTarget;

    const process_argv = try allocProcessArgv(allocator, argv);
    defer freeProcessArgv(allocator, process_argv);

    var stdin_pipe: [2]std.c.fd_t = undefined;
    var stdout_pipe: [2]std.c.fd_t = undefined;
    if (std.c.pipe(&stdin_pipe) != 0) return error.ProcessSpawnFailed;
    errdefer {
        _ = std.c.close(stdin_pipe[0]);
        _ = std.c.close(stdin_pipe[1]);
    }
    if (std.c.pipe(&stdout_pipe) != 0) return error.ProcessSpawnFailed;
    errdefer {
        _ = std.c.close(stdout_pipe[0]);
        _ = std.c.close(stdout_pipe[1]);
    }

    const fork_rc = std.c.fork();
    if (fork_rc < 0) return error.ProcessSpawnFailed;
    if (fork_rc == 0) {
        _ = std.c.close(stdin_pipe[1]);
        _ = std.c.close(stdout_pipe[0]);
        if (std.c.dup2(stdin_pipe[0], std.posix.STDIN_FILENO) < 0) std.c._exit(127);
        if (std.c.dup2(stdout_pipe[1], std.posix.STDOUT_FILENO) < 0) std.c._exit(127);
        _ = std.c.close(stdin_pipe[0]);
        _ = std.c.close(stdout_pipe[1]);
        execCommand(process_argv.storage.ptr);
    }

    _ = std.c.close(stdin_pipe[0]);
    _ = std.c.close(stdout_pipe[1]);
    return .{
        .pid = @intCast(fork_rc),
        .stdin_fd = stdin_pipe[1],
        .stdout_fd = stdout_pipe[0],
    };
}

pub fn runProcessAlloc(allocator: std.mem.Allocator, argv: []const []const u8, stdin_bytes: ?[]const u8, max_stdout_bytes: usize) ![]u8 {
    if (comptime builtin.os.tag == .wasi or builtin.os.tag == .freestanding or builtin.os.tag == .windows) return error.UnsupportedTarget;

    const process_argv = try allocProcessArgv(allocator, argv);
    defer freeProcessArgv(allocator, process_argv);

    var stdin_pipe: [2]std.c.fd_t = undefined;
    var stdout_pipe: [2]std.c.fd_t = undefined;
    if (std.c.pipe(&stdin_pipe) != 0) return error.ProcessSpawnFailed;
    errdefer {
        _ = std.c.close(stdin_pipe[0]);
        _ = std.c.close(stdin_pipe[1]);
    }
    if (std.c.pipe(&stdout_pipe) != 0) return error.ProcessSpawnFailed;
    errdefer {
        _ = std.c.close(stdout_pipe[0]);
        _ = std.c.close(stdout_pipe[1]);
    }

    const fork_rc = std.c.fork();
    if (fork_rc < 0) return error.ProcessSpawnFailed;
    if (fork_rc == 0) {
        _ = std.c.close(stdin_pipe[1]);
        _ = std.c.close(stdout_pipe[0]);
        if (std.c.dup2(stdin_pipe[0], std.posix.STDIN_FILENO) < 0) std.c._exit(127);
        if (std.c.dup2(stdout_pipe[1], std.posix.STDOUT_FILENO) < 0) std.c._exit(127);
        _ = std.c.close(stdin_pipe[0]);
        _ = std.c.close(stdout_pipe[1]);
        execCommand(process_argv.storage.ptr);
    }

    const pid: std.c.pid_t = @intCast(fork_rc);
    _ = std.c.close(stdin_pipe[0]);
    stdin_pipe[0] = -1;
    _ = std.c.close(stdout_pipe[1]);
    stdout_pipe[1] = -1;

    var stdin_writer: ProcessStdinWriter = undefined;
    var has_stdin_writer = false;
    var stdin_thread: ?std.Thread = null;
    if (stdin_bytes) |bytes| {
        if (bytes.len != 0) {
            stdin_writer = .{ .fd = stdin_pipe[1], .bytes = bytes };
            has_stdin_writer = true;
            stdin_thread = std.Thread.spawn(.{}, writeProcessStdin, .{&stdin_writer}) catch |err| {
                _ = std.c.close(stdin_pipe[1]);
                stdin_pipe[1] = -1;
                _ = std.c.close(stdout_pipe[0]);
                stdout_pipe[0] = -1;
                _ = waitProcess(pid) catch {};
                return err;
            };
        } else {
            _ = std.c.close(stdin_pipe[1]);
        }
    } else {
        _ = std.c.close(stdin_pipe[1]);
    }
    stdin_pipe[1] = -1;

    const stdout = readFdAlloc(allocator, stdout_pipe[0], max_stdout_bytes) catch |err| {
        if (stdin_thread) |thread| thread.join();
        _ = waitProcess(pid) catch {};
        return err;
    };
    errdefer allocator.free(stdout);
    _ = std.c.close(stdout_pipe[0]);
    stdout_pipe[0] = -1;

    if (stdin_thread) |thread| thread.join();
    var process_err: ?anyerror = null;
    waitProcess(pid) catch |err| {
        process_err = err;
    };
    if (has_stdin_writer) if (stdin_writer.err) |err| return err;
    if (process_err) |err| return err;
    return stdout;
}

pub fn writeFile(path: []const u8, data: []const u8) !void {
    const file = try openFileWrite(path);
    defer file.close();
    try file.writeAll(data);
}

pub fn appendFile(path: []const u8, data: []const u8) !void {
    const file = try openFileAppend(path);
    defer file.close();
    try file.writeAll(data);
}

pub fn writeFdAll(fd: Fd, bytes: []const u8) !void {
    if (comptime !host_has_posix) return error.UnsupportedTarget;
    var index: usize = 0;
    while (index < bytes.len) {
        const rc = std.c.write(fd, bytes.ptr + index, bytes.len - index);
        switch (std.posix.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return error.WriteFailed;
                index += @intCast(rc);
            },
            .INTR => continue,
            else => return error.WriteFailed,
        }
    }
}

pub fn getEnvVarOwned(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    if (comptime builtin.os.tag == .wasi or builtin.os.tag == .freestanding) return error.EnvironmentVariableNotFound;
    const name_z = try allocator.dupeSentinel(u8, name, 0);
    defer allocator.free(name_z);
    const raw = std.c.getenv(name_z.ptr) orelse return error.EnvironmentVariableNotFound;
    return try allocator.dupe(u8, std.mem.span(raw));
}

pub fn realpathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (comptime builtin.os.tag == .freestanding or builtin.os.tag == .wasi or builtin.os.tag == .watchos) {
        return try allocator.dupe(u8, path);
    }
    const path_z = try allocator.dupeSentinel(u8, path, 0);
    defer allocator.free(path_z);
    var resolved_buf: [std.fs.max_path_bytes]u8 = undefined;
    const resolved = std.c.realpath(path_z.ptr, resolved_buf[0..].ptr) orelse return error.FileNotFound;
    return try allocator.dupe(u8, std.mem.span(resolved));
}

pub fn monotonicNanos() u64 {
    if (comptime builtin.os.tag == .freestanding or builtin.os.tag == .wasi) return 0;
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &ts) != 0) return 0;
    const sec: u128 = @intCast(ts.sec);
    const nsec: u128 = @intCast(ts.nsec);
    return @intCast(sec * std.time.ns_per_s + nsec);
}

pub fn monotonicMicros() i64 {
    return @intCast(monotonicNanos() / std.time.ns_per_us);
}

pub fn sleepNanos(nanos: u64) void {
    if (comptime builtin.os.tag == .freestanding or builtin.os.tag == .wasi) return;
    var req: std.c.timespec = .{
        .sec = @intCast(nanos / std.time.ns_per_s),
        .nsec = @intCast(nanos % std.time.ns_per_s),
    };
    while (std.c.nanosleep(&req, &req) != 0) {
        if (std.posix.errno(-1) != .INTR) return;
    }
}

pub fn randomBytes(buffer: []u8) void {
    if (comptime builtin.os.tag == .wasi or builtin.os.tag == .freestanding) {
        @memset(buffer, 0);
        return;
    }
    if (comptime @TypeOf(std.c.arc4random_buf) != void) {
        std.c.arc4random_buf(buffer.ptr, buffer.len);
        return;
    }
    const fd = std.posix.openat(std.posix.AT.FDCWD, "/dev/urandom", .{ .ACCMODE = .RDONLY }, 0) catch {
        @memset(buffer, 0);
        return;
    };
    defer _ = std.c.close(fd);
    var index: usize = 0;
    while (index < buffer.len) {
        const n = std.posix.read(fd, buffer[index..]) catch break;
        if (n == 0) break;
        index += n;
    }
    if (index < buffer.len) @memset(buffer[index..], 0);
}
