defmodule CruciblePolicy.Policy do
  @moduledoc """
  Deterministic first-slice policy over a forward trace.
  """

  alias CruciblePolicy.{PolicyPlan, RouteDecision, Uncertainty}
  alias CrucibleSignalTrace.ForwardTrace

  def decide(%ForwardTrace{} = trace, opts \\ []) do
    plan = opts |> Keyword.get(:plan, %{}) |> PolicyPlan.new()
    uncertainty = Uncertainty.from_trace(trace)

    {target, confidence} =
      cond do
        Uncertainty.high?(uncertainty, plan.high_entropy_threshold) ->
          {:verifier, plan.verifier_confidence}

        planning_task?(trace) or moderate_uncertainty?(uncertainty, plan) ->
          {:thinker, plan.thinker_confidence}

        true ->
          {:worker, plan.worker_confidence}
      end

    {:ok,
     RouteDecision.new!(
       trace_id: trace.trace_id,
       policy_ref: plan.policy_ref,
       selected_target: target,
       selected_model: Keyword.get(opts, :selected_model, trace.model_ref),
       confidence: confidence,
       uncertainty: %{uncertainty | policy_confidence: confidence},
       evidence_refs: evidence_refs(trace),
       metadata: %{policy: :first_slice}
     )}
  end

  defp planning_task?(%ForwardTrace{} = trace) do
    Map.get(trace.metadata, :task_type) in [:planning, "planning", :decompose, "decompose"]
  end

  defp moderate_uncertainty?(%Uncertainty{} = uncertainty, %PolicyPlan{} = plan) do
    is_number(uncertainty.entropy) and uncertainty.entropy >= plan.moderate_entropy_threshold
  end

  defp evidence_refs(%ForwardTrace{} = trace) do
    trace.signal_records
    |> Enum.map(& &1.signal_ref.signal_id)
    |> Enum.reject(&is_nil/1)
  end
end
