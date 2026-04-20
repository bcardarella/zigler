defmodule Zig.BuildModule do
  @moduledoc false

  # this module encapulates a struct which carries attributes of extra zig modules
  # to be added.  The fields of the struct are subject to change as the capabilites of
  # zigler are increased, or new features are added in zig.

  @enforce_keys [:name, :path]

  defstruct @enforce_keys ++
              [
                :c,
                deps: [],
                root?: false,
                error_tracing: nil
              ]

  alias Zig.Builder
  use Builder, template: "templates/build_extra_mod.zig.eex"

  def from_beam_module(build) do
    %__MODULE__{
      name: :nif,
      path: Builder.nif_file(),
      deps:
        [:erl_nif, :beam, :attributes]
        |> maybe_add_easy_c_dep(build)
        |> maybe_add_translate_c_dep(build)
        |> Kernel.++(Enum.map(build.extra_modules, &module_spec/1)),
      c: build.c
    }
  end

  defp maybe_add_easy_c_dep(deps, %{easy_c: nil}), do: deps
  defp maybe_add_easy_c_dep(deps, _build), do: deps ++ [:easy_c]

  defp maybe_add_translate_c_dep(deps, %{translate_c: nil}), do: deps
  defp maybe_add_translate_c_dep(deps, _build), do: deps ++ [:c]

  defp module_spec(%{name: name}), do: name
  defp module_spec(%{dep: dep, src_mod: src_mod, dst_mod: dst_mod}), do: {dep, {src_mod, dst_mod}}

  # default modules

  def erl_nif do
    %__MODULE__{
      name: :erl_nif,
      path: Builder.beam_file("erl_nif.zig"),
      deps: [:erl_nif_raw]
    }
  end

  def stub_erl_nif do
    %__MODULE__{
      name: :erl_nif,
      path: Builder.beam_file("stub_erl_nif.zig")
    }
  end

  def beam do
    %__MODULE__{
      name: :beam,
      path: Builder.beam_file("beam.zig"),
      deps: [:erl_nif]
    }
  end

  def attributes do
    %__MODULE__{
      name: :attributes,
      path: "attributes.zig"
    }
  end

  def sema do
    %__MODULE__{
      name: :sema,
      path: Builder.beam_file("sema.zig"),
      deps: [:nif, :beam, :erl_nif],
      root?: true
    }
  end

  def nif_shim do
    %__MODULE__{
      name: :nif_shim,
      path: "module.zig",
      deps: [:beam, :erl_nif, :nif],
      root?: true
    }
  end
end
