const std = @import("std");
const builtin = @import("builtin");
const beam = @import("beam.zig");

var debug_threaded_io: std.Io.Threaded = undefined;
var debug_threaded_io_initialized = false;

fn getDebugIo() std.Io {
    if (!debug_threaded_io_initialized) {
        debug_threaded_io = std.Io.Threaded.init(std.heap.page_allocator, .{});
        debug_threaded_io_initialized = true;
    }

    return debug_threaded_io.io();
}

fn make_empty_trace_item(opts: anytype) beam.term {
    return beam.make(.{
        .source_location = null,
        .symbol_name = null,
        .compile_unit_name = null,
    }, opts);
}

fn make_trace_item(address: usize, opts: anytype) beam.term {
    const debug_info = std.debug.getSelfDebugInfo() catch return make_empty_trace_item(opts);
    const symbol_allocator_fallback_size = @sizeOf(std.debug.Symbol) + @alignOf(std.debug.Symbol) - 1;
    var symbol_fallback_allocator = std.heap.stackFallback(symbol_allocator_fallback_size, std.debug.getDebugInfoAllocator());
    const symbol_allocator = symbol_fallback_allocator.get();
    var symbols = std.ArrayList(std.debug.Symbol).initCapacity(symbol_allocator, 1) catch
        return make_empty_trace_item(opts);
    defer symbols.deinit(symbol_allocator);

    var text_arena = std.heap.ArenaAllocator.init(std.debug.getDebugInfoAllocator());
    defer text_arena.deinit();

    debug_info.getSymbols(
        getDebugIo(),
        symbol_allocator,
        text_arena.allocator(),
        address,
        false,
        &symbols,
    ) catch return make_empty_trace_item(opts);

    if (symbols.items.len == 0) return make_empty_trace_item(opts);
    const symbol_info = symbols.items[0];

    return beam.make(.{
        .source_location = symbol_info.source_location,
        .symbol_name = symbol_info.name,
        .compile_unit_name = symbol_info.compile_unit_name,
    }, opts);
}

pub fn to_term(stacktrace: *std.builtin.StackTrace, opts: anytype) beam.term {
    if (builtin.strip_debug_info) return beam.make(.nil, opts);

    var frame_index: usize = 0;
    var frames_left: usize = @min(stacktrace.index, stacktrace.instruction_addresses.len);
    var stacktrace_term = beam.make_empty_list(opts);

    stacktrace_term = stacktrace_term;

    while (frames_left != 0) : ({
        frames_left -= 1;
        frame_index = (frame_index + 1) % stacktrace.instruction_addresses.len;
    }) {
        const return_address = stacktrace.instruction_addresses[frame_index];
        const new_trace_item = make_trace_item(return_address -| 1, opts);
        stacktrace_term = beam.make_list_cell(new_trace_item, stacktrace_term, opts);
    }
    return stacktrace_term;
}
