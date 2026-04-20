use Protoss

defprotocol Zig.Builder do
  @moduledoc false

  # Code for interfacing with `std.build.Builder`, the interface for programmatically invoking
  # build code with the `zig build` command.

  @spec render_build(t) :: iodata()
  def render_build(assigns, opts)
after
  require EEx
  require Logger
  alias Zig.Attributes
  alias Zig.Command

  defmacro __using__(opts) do
    template = Keyword.fetch!(opts, :template)

    quote do
      defdelegate fetch(struct, key), to: Map

      require EEx
      render_template = Path.join(__DIR__, unquote(template))
      EEx.function_from_file(:def, :render_build, render_template, [:assigns, :opts])
      defoverridable render_build: 2
    end
  end

  def render_build(assigns), do: render_build(assigns, [])

  def staging_directory(module) do
    staging_root =
      case System.get_env("ZIGLER_STAGING_ROOT", "") do
        "" -> Zig._tmp_dir()
        path -> path
      end

    Path.join(staging_root, to_string(module))
  end

  # this is required because Elixir version < 1.16 doesn't support Path.relative_to/3
  def staging_directory(module, from) do
    staging_dir = staging_directory(module)

    # On Windows, always copy dependencies into the staging directory because
    # Zig's build.zig.zon requires relative paths, and Windows path issues
    # (different drives, path length limits) can make relative paths problematic.
    if :os.type() == {:win32, :nt} do
      {:copy, staging_dir, from}
    else
      normalized_staging = norm(staging_dir)
      normalized_from = norm(from)

      case {normalized_staging, normalized_from} do
        {<<drive>> <> ":/" <> mod_rest, <<drive>> <> ":/" <> from_rest} ->
          from_rest
          |> String.split("/")
          |> force_relative(String.split(mod_rest, "/"))

        {"/" <> mod_rest, "/" <> from_rest} ->
          from_rest
          |> String.split("/")
          |> force_relative(String.split(mod_rest, "/"))

        {dir_mod, _} ->
          Path.relative_to(from, dir_mod)
      end
    end
  end

  if {:win32, :nt} == :os.type() do
    defp norm(path) do
      path
      |> String.replace("\\", "/")
      |> case do
        <<a, ?:, rest::binary>> when a in ?A..?Z ->
          <<a + 32, ?:, rest::binary>>

        other ->
          other
      end
    end
  else
    defp norm(path), do: path
  end

  defp force_relative([same | rest_left], [same | rest_right]),
    do: force_relative(rest_left, rest_right)

  defp force_relative([], []), do: "."

  defp force_relative(left, others) do
    others
    |> length()
    |> then(&List.duplicate("..", &1))
    |> Path.join()
    |> Path.join(Path.join(left))
  end

  EEx.function_from_file(
    :def,
    :build_zig_zon,
    Path.join(__DIR__, "templates/build.zig.zon.eex"),
    [:assigns]
  )

  def beam_file(path) do
    Path.join("zigler_beam", path)
  end

  def erl_nif_win_dir do
    "zigler_erl_nif_win"
  end

  def erl_include_dir do
    "zigler_erl_include"
  end

  def erl_nif_header_file do
    "zigler_erl_nif.h"
  end

  def nif_file do
    "nif.zig"
  end

  def stage(module = %{precompiled: nil}) do
    staging_directory = staging_directory(module.module)

    unless File.dir?(staging_directory) do
      Logger.debug("creating staging directory #{staging_directory}")

      # Verify the staging root exists before trying to create subdirectories
      # The staging root should already exist - we only create the module-specific subdirectory
      staging_root =
        case System.get_env("ZIGLER_STAGING_ROOT", "") do
          "" -> Zig._tmp_dir()
          path -> path
        end

      unless File.dir?(staging_root) do
        raise File.Error,
          reason: :enoent,
          action: "make directory (with -p)",
          path: staging_directory
      end

      File.mkdir!(staging_directory)
    end

    libc_txt = build_libc_file(staging_directory)
    copy_beam_support_files!(staging_directory)
    File.cp!(module.zig_code_path, Path.join(staging_directory, nif_file()))
    copy_transitive_zig_imports!(module.zig_code_path, staging_directory)
    File.write!(Path.join(staging_directory, erl_nif_header_file()), erl_nif_header())

    # TODO: move to Attributes module.
    attribs_path = Path.join(staging_directory, "attributes.zig")
    File.write!(attribs_path, Enum.map(module.attributes, &Attributes.render_zig/1))

    if module.easy_c do
      easy_c_path = Path.join(staging_directory, "easy_c.h")
      File.write!(easy_c_path, easy_c_header(module.easy_c))
    end

    if module.translate_c do
      translate_c_path = Path.join(staging_directory, "zigler_translate_c.h")
      File.write!(translate_c_path, translate_c_header(module.translate_c))
    end

    build_zig_path = Path.join(staging_directory, "build.zig")
    build_zig_zon_path = Path.join(staging_directory, "build.zig.zon")

    if dir = module.build_files_dir do
      source_dir = Zig._normalize_path(dir, Path.dirname(module.file))

      # Process dependencies even when using build_files_dir
      process_dependencies(module, staging_directory)
      copy_build_files_dir!(source_dir, staging_directory)

      source_dir
      |> Path.join("build.zig")
      |> File.cp!(build_zig_path)

      source_dir
      |> Path.join("build.zig.zon")
      |> File.cp!(build_zig_zon_path)
    else
      # Process dependencies - copy them if needed on Windows
      processed_dependencies = process_dependencies(module, staging_directory)

      File.write!(build_zig_path, render_build(%{module | libc_txt: libc_txt}))
      Command.fmt(build_zig_path)

      File.write!(
        build_zig_zon_path,
        build_zig_zon(%{module | dependencies: processed_dependencies})
      )
    end

    Logger.debug("wrote build.zig to #{build_zig_path}")

    %{module | module_code_path: Path.join(staging_directory, "module.zig")}
  rescue
    e in File.Error ->
      new_action = "#{e.action}, consider setting ZIGLER_STAGING_ROOT environment variable\n"
      reraise %{e | action: new_action}, __STACKTRACE__
  end

  # if precompiled file is specified, do nothing.
  def stage(module), do: module

  defp process_dependencies(module, staging_directory) do
    Enum.map(module.dependencies, fn {name, path} ->
      case staging_directory(module.module, path) do
        {:copy, _staging_dir, from} ->
          # Need to copy the dependency into the staging directory
          deps_dir = Path.join(staging_directory, "deps")
          File.mkdir_p!(deps_dir)

          dep_name = Path.basename(from)
          dest = Path.join(deps_dir, dep_name)

          # Copy the entire dependency directory
          Logger.debug("copying dependency #{from} to #{dest}")
          File.cp_r!(from, dest)

          # Return the dependency with the new relative path
          {name, "./deps/#{dep_name}"}

        relative_path ->
          # Normal case - use the relative path as-is
          {name, relative_path}
      end
    end)
  end

  defp build_libc_file(staging_directory) do
    # build a libc file for windows-msvc target
    if match?({_, :windows, :msvc, _}, Application.get_env(:zigler, :precompiling)) do
      staging_directory
      |> Path.join("libc.txt")
      |> File.write!(libc())

      "libc.txt"
    end
  end

  defp libc do
    Regex.replace(
      ~r/\$\{([A-Z0-9_]+)\}/,
      """
      # The directory that contains `stdlib.h` (UCRT headers from the Windows SDK)
      include_dir=${WINSDK_ROOT}/Include/${WINSDK_VER}/ucrt

      # The system-specific include directory (MSVC headers; contains vcruntime.h)
      sys_include_dir=${MSVC_ROOT}/include

      # For Windows, point this to the UCRT library directory in the SDK
      # (Zig uses this field for the CRT libraries on Windows)
      crt_dir=${WINSDK_ROOT}/Lib/${WINSDK_VER}/ucrt/x64

      # MSVC libraries (contains vcruntime.lib, etc.)
      msvc_lib_dir=${MSVC_ROOT}/lib/x64

      # Windows SDK "um" libraries (contains kernel32.lib, user32.lib, etc.)
      kernel32_lib_dir=${WINSDK_ROOT}/Lib/${WINSDK_VER}/um/x64

      # Not used on Windows
      gcc_dir=
      """,
      fn _, var -> System.fetch_env!(var) end
    )
  end

  defp easy_c_header(header) do
    include_directive(header)
  end

  defp translate_c_header(headers) do
    headers
    |> Enum.map_join("", &include_directive/1)
  end

  defp include_directive(header) do
    {open, close, include_path} =
      if File.exists?(header) do
        {"\"", "\"", header}
      else
        {"<", ">", Path.basename(header)}
      end

    escaped_header =
      include_path
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")

    "#include #{open}#{escaped_header}#{close}\n"
  end

  defp erl_nif_header do
    """
    #ifdef _WIN32
    #include \"erl_nif_win.h\"
    #else
    #include \"erl_nif.h\"
    #endif
    """
  end

  defp copy_beam_support_files!(staging_directory) do
    beam_source_dir =
      :zigler
      |> :code.priv_dir()
      |> Path.join("beam")

    beam_dest_dir = Path.join(staging_directory, "zigler_beam")
    File.rm_rf!(beam_dest_dir)
    File.cp_r!(beam_source_dir, beam_dest_dir)

    erl_nif_win_source_dir =
      :zigler
      |> :code.priv_dir()
      |> Path.join("erl_nif_win")

    erl_nif_win_dest_dir = Path.join(staging_directory, erl_nif_win_dir())
    File.rm_rf!(erl_nif_win_dest_dir)
    File.cp_r!(erl_nif_win_source_dir, erl_nif_win_dest_dir)

    erl_include_source_dir =
      Path.join([:code.root_dir(), "/erts-#{:erlang.system_info(:version)}", "/include"])

    erl_include_dest_dir = Path.join(staging_directory, erl_include_dir())
    File.rm_rf!(erl_include_dest_dir)
    File.cp_r!(erl_include_source_dir, erl_include_dest_dir)
  end

  defp copy_transitive_zig_imports!(zig_code_path, staging_directory) do
    source_dir = Path.dirname(zig_code_path)
    zig_code = File.read!(zig_code_path)
    do_copy_transitive_zig_imports!(zig_code, source_dir, staging_directory, MapSet.new())
  end

  defp do_copy_transitive_zig_imports!(zig_code, source_dir, staging_directory, seen) do
    Regex.scan(~r/@import\("([^"]+\.zig)"\)/, zig_code)
    |> Enum.reduce(seen, fn [_, import_path], seen ->
      source_path = Path.join(source_dir, import_path)

      if import_path in seen or not File.exists?(source_path) do
        seen
      else
        seen = MapSet.put(seen, import_path)
        dest_path = Path.join(staging_directory, import_path)
        File.cp!(source_path, dest_path)

        imported_code = File.read!(source_path)
        do_copy_transitive_zig_imports!(imported_code, source_dir, staging_directory, seen)
      end
    end)
  end

  defp copy_build_files_dir!(source_dir, staging_directory) do
    destination_dir = Path.join(staging_directory, "build_files")
    File.rm_rf!(destination_dir)
    File.mkdir_p!(destination_dir)

    source_dir
    |> File.ls!()
    |> Enum.reject(&(&1 in ["build.zig", "build.zig.zon"] or String.starts_with?(&1, ".")))
    |> Enum.each(fn entry ->
      source = Path.join(source_dir, entry)
      destination = Path.join(destination_dir, entry)

      case File.stat!(source).type do
        :directory ->
          File.cp_r!(source, destination)

        _ ->
          File.cp!(source, destination)
      end
    end)
  end
end
