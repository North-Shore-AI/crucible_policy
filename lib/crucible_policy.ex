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

  @doc "Evaluates a completed forward trace with a policy plan."
  def evaluate(plan, trace, opts \\ []), do: CruciblePolicy.PolicyPlan.evaluate(plan, trace, opts)

  @doc "Evaluates one incremental signal record at a token boundary."
  def evaluate_signal(plan, record, context),
    do: CruciblePolicy.PolicyPlan.evaluate_signal(plan, record, context)

  @doc "Evaluates a trace fragment containing one or more incremental signal records."
  def evaluate_incremental(plan, fragment, context),
    do: CruciblePolicy.PolicyPlan.evaluate_incremental(plan, fragment, context)
end
