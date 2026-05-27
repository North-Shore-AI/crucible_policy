defmodule CruciblePolicy.Policy do
  @moduledoc """
  Deterministic first-slice policy over a forward trace.
  """

  alias CruciblePolicy.{PolicyPlan, RouteDecision, Uncertainty}
  alias CrucibleSignalTrace.ForwardTrace

  def decide(%ForwardTrace{} = trace, opts \\ []) do
    plan = normalize_plan(Keyword.get(opts, :plan, %{}))
    uncertainty = Uncertainty.from_trace(trace)

    {target, confidence} =
      cond do
        verifier_required?(uncertainty, plan) ->
          {:verifier, plan.verifier_confidence}

        planning_task?(trace) or thinker_required?(uncertainty, plan) ->
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

  defp normalize_plan(%PolicyPlan{} = plan), do: plan
  defp normalize_plan(attrs), do: PolicyPlan.new(attrs)

  defp planning_task?(%ForwardTrace{} = trace) do
    Map.get(trace.metadata, :task_type) in [:planning, "planning", :decompose, "decompose"]
  end

  defp verifier_required?(%Uncertainty{} = uncertainty, %PolicyPlan{} = plan) do
    truthy?(uncertainty.nan_or_inf) or truthy?(uncertainty.norm_anomaly) or
      truthy?(uncertainty.cache_discontinuity) or
      contradictory_margin?(uncertainty, plan) or
      above_or_equal?(uncertainty.layer_drift, plan.trajectory_anomaly_threshold) or
      below_or_equal?(
        uncertainty.logit_lens_trajectory_stability,
        1.0 - plan.trajectory_anomaly_threshold
      ) or
      above_or_equal?(uncertainty.intra_model_logit_lens_kl, plan.intra_model_kl_threshold)
  end

  defp thinker_required?(%Uncertainty{} = uncertainty, %PolicyPlan{} = plan) do
    above_or_equal?(uncertainty.entropy, plan.moderate_entropy_threshold) or
      above_or_equal?(uncertainty.moe_router_entropy, plan.moderate_entropy_threshold)
  end

  defp contradictory_margin?(%Uncertainty{} = uncertainty, %PolicyPlan{} = plan) do
    below_or_equal?(uncertainty.margin, plan.verifier_margin_threshold) and
      not above_or_equal?(uncertainty.entropy, plan.high_entropy_threshold)
  end

  defp evidence_refs(%ForwardTrace{} = trace) do
    trace.signal_records
    |> Enum.map(& &1.signal_ref.signal_id)
    |> Enum.reject(&is_nil/1)
  end

  defp above_or_equal?(value, threshold), do: is_number(value) and value >= threshold
  defp below_or_equal?(value, threshold), do: is_number(value) and value <= threshold
  defp truthy?(value), do: value in [true, "true", 1]
end
