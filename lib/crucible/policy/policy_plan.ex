defmodule Crucible.Policy.PolicyPlan do
  @moduledoc """
  V4 offline policy replay with explicit degradation metadata.
  """

  alias Crucible.Policy.{
    FinalLogitsEntropyPolicy,
    FinalLogitsMarginPolicy,
    PolicyConfig
  }

  alias Crucible.PolicyDecision

  @policy_order [
    :final_logits_entropy_v0,
    :final_logits_margin_v0,
    :top_k_stability_v0,
    :spilled_energy_v0,
    :hidden_state_norm_drift_v0,
    :trajectory_drift_v1,
    :correction_plan_v0
  ]

  @spec evaluate(Crucible.ForwardTrace.t(), PolicyConfig.t()) :: PolicyDecision.t()
  def evaluate(trace, %PolicyConfig{} = config \\ %PolicyConfig{}) do
    entropy_result = FinalLogitsEntropyPolicy.evaluate(trace, config)
    margin_result = FinalLogitsMarginPolicy.evaluate(trace, config)

    {selected, evidence, skipped} =
      [entropy_result, margin_result]
      |> Enum.reduce({nil, [], []}, &collect_result/2)
      |> append_capability_skips(trace)

    selected = selected || %{policy: :final_logits_entropy_v0, action: :worker}

    %PolicyDecision{
      decision_id: "dec_#{System.unique_integer([:positive])}",
      trace_id: trace.trace_id,
      selected_policy: selected.policy,
      selected_action: selected.action,
      confidence: nil,
      evidence: Enum.reverse(evidence),
      skipped_policies: skipped,
      fallback_path: fallback_path(selected.policy),
      errors: []
    }
  end

  def policy_order, do: @policy_order

  defp collect_result({:ok, %{status: :triggered} = result}, {_selected, evidence, skipped}) do
    {result, [result.evidence | evidence], skipped}
  end

  defp collect_result({:ok, result}, {selected, evidence, skipped}) do
    {selected || result, [result.evidence | evidence], skipped}
  end

  defp collect_result({:skip, skipped_policy}, {selected, evidence, skipped}) do
    {selected, evidence, [skipped_policy | skipped]}
  end

  defp append_capability_skips({selected, evidence, skipped}, trace) do
    skipped =
      (skipped ++
         [
           missing_signal_skip(trace, :generation_step_logits, :spilled_energy_v0),
           missing_signal_skip(trace, :hidden_state, :hidden_state_norm_drift_v0),
           missing_signal_skip(trace, :hidden_state, :trajectory_drift_v1),
           unsupported_capability_skip(trace, :active_correction, :correction_plan_v0)
         ])
      |> Enum.reject(&is_nil/1)

    {selected, evidence, skipped}
  end

  defp missing_signal_skip(trace, signal_type, policy) do
    if Enum.any?(trace.signals, &(&1.signal_type == signal_type)) do
      nil
    else
      %{policy: policy, reason: :"#{signal_type}_unavailable", required_signal: signal_type}
    end
  end

  defp unsupported_capability_skip(_trace, capability, policy) do
    %{policy: policy, reason: :capability_unavailable, required_signal: capability}
  end

  defp fallback_path(policy) do
    @policy_order
    |> Enum.take_while(&(&1 != policy))
    |> Kernel.++([policy])
  end
end
