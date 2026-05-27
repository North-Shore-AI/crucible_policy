defmodule CruciblePolicy do
  @moduledoc """
  Decision contracts over Crucible signal traces.

  This package owns routing, gating, fusion, uncertainty, verifier, shared
  memory, and steering decisions over model-internal signal evidence.
  """

  @version Mix.Project.config()[:version]

  @doc "Returns the package version."
  def version, do: @version

  @doc "Runs the deterministic first-slice policy over a forward trace."
  def decide(trace, opts \\ []), do: CruciblePolicy.Policy.decide(trace, opts)
end
