defmodule ZiglerTest.Cxx.CompileError do
  use Zig,
    otp_app: :zigler,
    translate_c: "compile_error.h",
    c: [include_dirs: "include", src: "src2/compile_error.c"]

  ~Z"""
  const c = @import("c");
  pub const foo = c.foo;
  """
end
