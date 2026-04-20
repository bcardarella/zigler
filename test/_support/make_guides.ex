defmodule ZiglerTest.MakeGuides do
  defstruct lines: [], on: false, needs_module: true, has_use_zig: false, top: []

  def go do
    File.mkdir_p!("test/guides")

    "guides"
    |> File.ls!()
    |> Enum.each(fn
      "06-c_integration.md" ->
        :ok

      "11-precompiled.md" ->
        :ok

      filename ->
        if String.ends_with?(filename, ".md") do
          basename =
            filename
            |> Path.basename(".md")
            |> String.split("-")
            |> Enum.at(1)

          dest_filename = String.replace_suffix(basename, "", "_test.exs")

          dest_stream =
            "test/guides"
            |> Path.join(dest_filename)
            |> File.stream!([])

          "guides"
          |> Path.join(filename)
          |> File.stream!([], :line)
          |> Enum.reduce(%__MODULE__{needs_module: module(basename)}, &collect_sections/2)
          |> prepare
          |> Enum.into(dest_stream)
        end
    end)
  end

  defp collect_sections(line, acc = %{on: false}) do
    %{acc | on: String.trim(line) == "```elixir"}
  end

  defp collect_sections(line, acc) do
    if String.trim(line) == "```" do
      %{acc | on: false}
    else
      has_use_zig = acc.has_use_zig || String.contains?(line, "use Zig")
      %{acc | lines: [line | acc.lines], needs_module: !(line =~ "defmodule") && acc.needs_module, has_use_zig: has_use_zig}
    end
  end

  defp prepare(%{lines: [head | _] = lines, needs_module: false}) do
    tail = if head =~ "#", do: [], else: ["end\n"]

    Enum.reverse(lines, tail)
  end

  defp prepare(%{lines: lines, needs_module: module, has_use_zig: has_use_zig}) do
    [header(module, has_use_zig) | Enum.reverse(lines, ["end\n"])]
  end

  defp header(module, true) do
    """
    defmodule #{module} do
      use ExUnit.Case
    """
  end

  defp header(module, false) do
    """
    defmodule #{module} do
      use ExUnit.Case
      use Zig, otp_app: :zigler
    """
  end

  defp module(filename), do: "ZiglerTest.#{Macro.camelize(filename)}Test"
end
