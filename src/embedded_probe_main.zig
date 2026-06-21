const embedded = @import("embedded_api.zig");

const probe_heap_bytes = 64 * 1024;

export var kiwi_embedded_probe_heap: [probe_heap_bytes]u8 align(16) = undefined;
export var kiwi_embedded_probe_output: [64]u8 = undefined;
export var kiwi_embedded_probe_result_len: isize = 0;

export fn _start() noreturn {
    _ = embedded.kiwi_embedded_set_heap(&kiwi_embedded_probe_heap, kiwi_embedded_probe_heap.len);
    const source = "1+2";
    const result_len = embedded.kiwi_embedded_eval_once(source.ptr, source.len, &kiwi_embedded_probe_output, kiwi_embedded_probe_output.len);
    @as(*volatile isize, &kiwi_embedded_probe_result_len).* = result_len;
    while (true) {}
}
