///////////////////////////////////////////////////////////////////////////////
// NIF LOADING Boilerplate functions.

const beam = @import("beam.zig");
const e = @import("erl_nif");

fn prepare_callback_context(env: beam.env) void {
    beam.context.env = env;
    beam.context.mode = .callback;
    beam.context.allocator = beam.allocator;
}

fn adapt_load_return(comptime ReturnType: type, value: ReturnType) c_int {
    return switch (@typeInfo(ReturnType)) {
        .void => 0,
        .int => @intCast(value),
        .@"enum" => @intFromEnum(value),
        else => @compileError("unsupported on_load return type"),
    };
}

fn adapt_upgrade_return(comptime ReturnType: type, value: ReturnType) c_int {
    return switch (@typeInfo(ReturnType)) {
        .void => 0,
        .int => @intCast(value),
        .@"enum" => @intFromEnum(value),
        else => @compileError("unsupported on_upgrade return type"),
    };
}

pub fn run_on_load(comptime function: anytype, env: beam.env, priv_data: [*c]?*anyopaque, load_info: e.ErlNifTerm) c_int {
    prepare_callback_context(env);

    const fn_info = @typeInfo(@TypeOf(function)).@"fn";
    const ReturnType = fn_info.return_type orelse @compileError("on_load callback must have a return type");

    return switch (fn_info.params.len) {
        2 => blk: {
            const Payload = fn_info.params[1].type orelse @compileError("invalid on_load payload type");
            const payload = beam.get(Payload, .{ .v = load_info }, .{}) catch break :blk -1;

            switch (@typeInfo(ReturnType)) {
                .error_union => |eu| {
                    if (eu.payload != void) @compileError("on_load error return must resolve to void");
                    function(@ptrCast(priv_data), payload) catch |err| break :blk @intFromError(err);
                    break :blk 0;
                },
                else => break :blk adapt_load_return(ReturnType, function(@ptrCast(priv_data), payload)),
            }
        },
        3 => function(env, @ptrCast(priv_data), load_info),
        else => @compileError("invalid on_load callback arity"),
    };
}

pub fn run_on_upgrade(comptime function: anytype, env: beam.env, priv_data: [*c]?*anyopaque, old_priv_data: [*c]?*anyopaque, load_info: e.ErlNifTerm) c_int {
    prepare_callback_context(env);

    const fn_info = @typeInfo(@TypeOf(function)).@"fn";
    const ReturnType = fn_info.return_type orelse @compileError("on_upgrade callback must have a return type");

    return switch (fn_info.params.len) {
        3 => blk: {
            const Payload = fn_info.params[2].type orelse @compileError("invalid on_upgrade payload type");
            const payload = beam.get(Payload, .{ .v = load_info }, .{}) catch break :blk -1;

            switch (@typeInfo(ReturnType)) {
                .error_union => |eu| {
                    if (eu.payload != void) @compileError("on_upgrade error return must resolve to void");
                    function(@ptrCast(priv_data), @ptrCast(old_priv_data), payload) catch break :blk -1;
                    break :blk 0;
                },
                else => break :blk adapt_upgrade_return(ReturnType, function(@ptrCast(priv_data), @ptrCast(old_priv_data), payload)),
            }
        },
        4 => function(env, @ptrCast(priv_data), @ptrCast(old_priv_data), load_info),
        else => @compileError("invalid on_upgrade callback arity"),
    };
}

pub fn run_on_unload(comptime function: anytype, env: beam.env, priv_data: ?*anyopaque) void {
    prepare_callback_context(env);

    const fn_info = @typeInfo(@TypeOf(function)).@"fn";
    switch (fn_info.params.len) {
        1 => function(@ptrCast(@alignCast(priv_data))),
        2 => function(env, priv_data),
        else => @compileError("invalid on_unload callback arity"),
    }
}

pub export fn blank_load(_: beam.env, _: ?*?*anyopaque, _: e.ErlNifTerm) c_int {
    return 0;
}

pub export fn blank_upgrade(_: beam.env, _: ?*?*anyopaque, _: ?*?*anyopaque, _: e.ErlNifTerm) c_int {
    return 0;
}

pub export fn blank_unload(_: beam.env, _: ?*anyopaque) void {}
