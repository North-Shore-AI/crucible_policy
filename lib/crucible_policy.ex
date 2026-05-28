defmodule CruciblePolicy do
  @moduledoc """
  Decision contracts over Crucible signal traces.

  This package owns routing, gating, fusion, uncertainty, verifier, shared
  memory, and steering decisions over model-internal signal evidence.
  """

  @version Mix.Project.config()[:version]

  @doc "Returns the package version."
  def version, do: @version

  @doc "Runs the deterministic route policy over a canonical forward trace."
  def decide(trace, opts \\ []), do: CruciblePolicy.Policy.decide(trace, opts)

  @doc "Evaluates a completed forward trace with a policy plan."
  def evaluate(plan, trace, opts \\ []), do: CruciblePolicy.PolicyPlan.evaluate(plan, trace, opts)

  @doc "Builds a bounded cross-model comparison report for canonical Crucible traces."
  def compare_traces(traces, opts \\ []) when is_list(traces) do
    config = Keyword.get(opts, :config, %Crucible.Policy.PolicyConfig{})
    Crucible.Policy.CrossModelComparison.compare(traces, config)
  end

  @doc "Evaluates one incremental signal record at a token boundary."
  def evaluate_signal(plan, record, context),
    do: CruciblePolicy.PolicyPlan.evaluate_signal(plan, record, context)

  @doc "Evaluates a trace fragment containing one or more incremental signal records."
  def evaluate_incremental(plan, fragment, context),
    do: CruciblePolicy.PolicyPlan.evaluate_incremental(plan, fragment, context)
end
