defmodule Crucible.Policy.PolicyPlan do
  @moduledoc """
  V5 offline policy replay with explicit degradation metadata.
  """

  alias Crucible.Policy.{
    FinalLogitsEntropyPolicy,
    FinalLogitsMarginPolicy,
    HiddenStateNormDriftPolicy,
    CorrectionPlanPolicy,
    SpilledEnergyPolicy,
    TopKStabilityPolicy,
    TrajectoryDriftPolicy,
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
    {selected, evidence, skipped} =
      [
        FinalLogitsEntropyPolicy.evaluate(trace, config),
        FinalLogitsMarginPolicy.evaluate(trace, config),
        TopKStabilityPolicy.evaluate(trace, config),
        SpilledEnergyPolicy.evaluate(trace, config),
        HiddenStateNormDriftPolicy.evaluate(trace, config),
        TrajectoryDriftPolicy.evaluate(trace, config),
        CorrectionPlanPolicy.evaluate(trace, config)
      ]
      |> Enum.reduce({nil, [], []}, &collect_result/2)

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

  defp fallback_path(policy) do
    @policy_order
    |> Enum.take_while(&(&1 != policy))
    |> Kernel.++([policy])
  end
end
