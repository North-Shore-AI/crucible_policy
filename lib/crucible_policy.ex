defmodule CruciblePolicy do
  @moduledoc """
  Decision contracts over Crucible signal traces.

  This package owns routing, gating, fusion, uncertainty, verifier, shared
  memory, and steering decisions over model-internal signal evidence.
  """

  @version Mix.Project.config()[:version]

  @doc "Returns the package version."
  def version, do: @version
end
