const std = @import("std");
const nif = @import("nif");
const beam = @import("beam");
const e = @import("erl_nif");
const core = @import("sema_core.zig");

const special_types = .{
    .{ .enabled = true, .type = beam.term, .name = "term" },
    .{ .enabled = true, .type = e.ErlNifTerm, .name = "erl_nif_term" },
    .{ .enabled = true, .type = e.ErlNifEvent, .name = "e.ErlNifEvent" },
    .{ .enabled = true, .type = e.ErlNifBinary, .name = "e.ErlNifBinary" },
    .{ .enabled = true, .type = beam.pid, .name = "pid" },
    .{ .enabled = true, .type = beam.env, .name = "env" },
};

pub fn main(init: std.process.Init) !void {
    try core.main(init, nif, .{}, special_types);
}
