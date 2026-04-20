const std = @import("std");
const stubs = @import("sema_stubs.zig");
const analyte = @import("analyte");
const e = @import("erl_nif");
const core = @import("sema_core.zig");

const has_term = @hasDecl(analyte, "term");
const has_pid = @hasDecl(analyte, "pid");
const has_env = @hasDecl(analyte, "env");

const special_types = .{
    .{ .enabled = has_term, .type = if (has_term) analyte.term else void, .name = "term" },
    .{ .enabled = true, .type = e.ErlNifTerm, .name = "erl_nif_term" },
    .{ .enabled = true, .type = e.ErlNifEvent, .name = "e.ErlNifEvent" },
    .{ .enabled = true, .type = e.ErlNifBinary, .name = "e.ErlNifBinary" },
    .{ .enabled = has_pid, .type = if (has_pid) analyte.pid else void, .name = "pid" },
    .{ .enabled = has_env, .type = if (has_env) analyte.env else void, .name = "env" },
};

pub fn main(init: std.process.Init) !void {
    try core.main(init, analyte, stubs.functions, special_types);
}
