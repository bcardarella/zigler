defmodule ZiglerTest.CornerCases.BuildFilesOverrideTest do
  use ExUnit.Case, async: true

  use Zig, otp_app: :zigler, build_files_dir: "build_files"

  ~Z"""
  pub const add_one = @import("module").add_one;
  """

  test "directly using file works" do
    assert 48 = add_one(47)
  end
end
