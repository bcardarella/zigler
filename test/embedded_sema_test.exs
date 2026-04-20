defmodule ZiglerTest.EmbeddedSema do
  use Zig, otp_app: :zigler

  ~Z"""
  pub fn add_one(x: u32) u32 {
      return x + 1;
  }
  """
end

defmodule ZiglerTest.EmbeddedSemaTest do
  require Logger

  alias Zig.Sema

  use ExUnit.Case, async: true

  if {:win32, :nt} == :os.type() do
    @suffix "dll"
  else
    @suffix "so"
  end

  @filename "Elixir.ZiglerTest.EmbeddedSema.#{@suffix}"

  test "sidecar sema metadata" do
    file =
      :zigler
      |> :code.priv_dir()
      |> Path.join("lib")
      |> Path.join(@filename)

    tmp_dir = Path.join(System.tmp_dir!(), "zigler_embedded_sema")
    File.mkdir_p!(tmp_dir)

    tmp_file = Path.join(tmp_dir, @filename)
    tmp_sema_file = tmp_file <> ".sema.json"

    File.cp!(file, tmp_file)
    File.cp!(file <> ".sema.json", tmp_sema_file)

    {_, sema_text} = Sema._obtain_precompiled_sema_json(%{precompiled: tmp_file})
    assert %{"functions" => [%{"name" => "add_one"}]} = Zig._json_decode!(sema_text)
  end
end
