defmodule CruciblePolicy.PolicyPlanTest do
  use ExUnit.Case, async: true

  alias Crucible.{ForwardTrace, SignalRecord, TensorSummary}
  alias CruciblePolicy.{DecisionContext, PolicyPlan, RouteDecision, SteeringPlan}
  alias CrucibleSignalTrace.LayerTrajectory

  @plan PolicyPlan.new()

  test "worker fixture resolves to worker" do
    trace = trace_with_logits("worker", [10.0, 0.0, -1.0])

    assert {:ok, %RouteDecision{} = decision} = PolicyPlan.evaluate(@plan, trace)
    assert decision.selected_target == :worker
  end

  test "thinker fixture resolves to thinker for high entropy" do
    trace = trace_with_logits("thinker", List.duplicate(0.0, 24))

    assert {:ok, %RouteDecision{} = decision} = PolicyPlan.evaluate(@plan, trace)
    assert decision.selected_target == :thinker
  end

  test "verifier fixture resolves to verifier for output contradiction" do
    trace = trace_with_logits("verifier", [1.0, 0.98, 0.0])

    assert {:ok, %RouteDecision{} = decision} = PolicyPlan.evaluate(@plan, trace)
    assert decision.selected_target == :verifier
  end

  test "trajectory anomaly fixture resolves to verifier before final-logit commitment" do
    trace =
      ForwardTrace.new!(
        trace_id: "trace-trajectory-anomaly",
        model_id: "model:fixture",
        layer_trajectory:
          LayerTrajectory.new!([
            %{layer_index: 12, vector: [1.0, 0.0]},
            %{layer_index: 16, vector: [-1.0, 0.0]}
          ]),
        signals: [
          logits_record("trace-trajectory-anomaly", [10.0, 0.0, -1.0])
        ]
      )

    assert {:ok, %RouteDecision{} = decision} = PolicyPlan.evaluate(@plan, trace)
    assert decision.selected_target == :verifier
    assert decision.decision.uncertainty.logit_lens_trajectory_stability == 0.0
  end

  test "incremental evaluation returns a route halt for high entropy events" do
    context =
      DecisionContext.new(
        trace_id: "trace-fragment",
        runtime_profile: %{model_id: "model:fixture"}
      )

    fragment = %{signals: [logits_record("trace-fragment", List.duplicate(0.0, 24))]}

    assert {:halt, %RouteDecision{} = decision, next_context} =
             PolicyPlan.evaluate_incremental(@plan, fragment, context)

    assert decision.selected_target == :thinker
    assert next_context.running_entropy.count == 1
  end

  test "incremental evaluation returns token-boundary steering for moderate entropy events" do
    plan = PolicyPlan.new(high_entropy_threshold: 10.0, steering_entropy_threshold: 1.0)

    context =
      DecisionContext.new(trace_id: "trace-steer", runtime_profile: %{model_id: "model:fixture"})

    assert {:steer, %SteeringPlan{} = steering, _next_context} =
             PolicyPlan.evaluate_signal(
               plan,
               logits_record("trace-steer", [0.0, 0.0, 0.0]),
               context
             )

    assert steering.mode == :token_boundary
    assert [%{source: :policy_rule, kind: :uncertainty}] = steering.energies
  end

  test "early-exit gates fail closed unless the surface advertises support" do
    context =
      DecisionContext.new(
        surface_id: "surface:standard",
        metadata: %{capabilities: [:hidden_states]}
      )

    assert {:error, %{reason: :backend_not_supported, required_capability: :early_exit}} =
             PolicyPlan.negotiate_early_exit(@plan, %{required: true}, context)

    capable =
      DecisionContext.new(surface_id: "surface:custom", metadata: %{capabilities: [:early_exit]})

    assert {:ok, %{action: :early_exit, kind: :gate}} =
             PolicyPlan.negotiate_early_exit(@plan, %{}, capable)
  end

  test "policy replay evaluates canonical forward traces with skip metadata" do
    trace = %Crucible.ForwardTrace{
      trace_id: "trace-policy",
      provider_kind: :elixir_bumblebee,
      model_id: "hf-internal-testing/tiny-random-gpt2",
      signals: [
        %Crucible.SignalRecord{
          signal_id: "sig-final-logits",
          trace_id: "trace-policy",
          signal_type: :final_logits,
          tensor_summary:
            Crucible.TensorSummary.compute([3.0, 2.75, 0.0], entropy: true, top_k: 3)
        }
      ]
    }

    assert %Crucible.PolicyDecision{} = decision = Crucible.Policy.PolicyPlan.evaluate(trace)
    assert decision.selected_policy == :final_logits_margin_v0
    assert decision.selected_action == :verifier
    assert Enum.any?(decision.skipped_policies, &(&1.policy == :trajectory_drift_v1))
  end

  test "policy replay executes top-k stability and spilled-energy policies" do
    trace =
      canonical_trace("trace-generation", [
        canonical_signal(:final_logits, [4.0, 1.0, 0.0]),
        canonical_signal(:generation_step_logits, [5.0, 4.0, 0.0], token_index: 0),
        canonical_signal(:generation_step_logits, [0.0, 1.0, 5.0], token_index: 1)
      ])

    config = %Crucible.Policy.PolicyConfig{
      top_k_stability_threshold: 0.75,
      spilled_energy_threshold: 0.01
    }

    assert %Crucible.PolicyDecision{} =
             decision =
             Crucible.Policy.PolicyPlan.evaluate(trace, config)

    assert Enum.any?(decision.evidence, &(&1.rule == :top_k_stability_floor))
    assert Enum.any?(decision.evidence, &(&1.rule == :spilled_energy_delta))
    refute Enum.any?(decision.skipped_policies, &(&1.policy == :spilled_energy_v0))
  end

  test "policy replay executes hidden-state norm drift when hidden states exist" do
    trace =
      canonical_trace("trace-hidden", [
        canonical_signal(:final_logits, [4.0, 1.0, 0.0]),
        canonical_signal(:hidden_state, [1.0, 0.0], layer_index: 0),
        canonical_signal(:hidden_state, [10.0, 0.0], layer_index: 1)
      ])

    assert %Crucible.PolicyDecision{} =
             decision =
             Crucible.Policy.PolicyPlan.evaluate(
               trace,
               %Crucible.Policy.PolicyConfig{hidden_norm_drift_threshold: 1.0}
             )

    assert decision.selected_policy == :hidden_state_norm_drift_v0
    assert decision.selected_action == :verifier
  end

  test "policy replay executes trajectory drift when intermediate logits exist" do
    trace =
      canonical_trace("trace-trajectory", [
        canonical_signal(:final_logits, [4.0, 1.0, 0.0]),
        canonical_signal(:intermediate_logits, [8.0, 0.0], layer_index: 0),
        canonical_signal(:intermediate_logits, [0.0, 0.0], layer_index: 1)
      ])

    assert %Crucible.PolicyDecision{} =
             decision =
             Crucible.Policy.PolicyPlan.evaluate(
               trace,
               %Crucible.Policy.PolicyConfig{trajectory_drift_threshold: 0.1}
             )

    assert decision.selected_policy == :trajectory_drift_v1
    assert decision.selected_action == :verifier
  end

  test "correction policy is dry-run only and skips without capability" do
    unsupported =
      canonical_trace("trace-no-correction", [canonical_signal(:final_logits, [4.0, 1.0])])

    unsupported_decision = Crucible.Policy.PolicyPlan.evaluate(unsupported)

    assert Enum.any?(
             unsupported_decision.skipped_policies,
             &(&1.policy == :correction_plan_v0 and &1.reason == :capability_unavailable)
           )

    supported =
      canonical_trace(
        "trace-correction",
        [canonical_signal(:final_logits, [4.0, 1.0])],
        capability_report: %{resource_budget: %{supports_active_injection?: true}}
      )

    supported_decision = Crucible.Policy.PolicyPlan.evaluate(supported)

    assert Enum.any?(
             supported_decision.evidence,
             &(&1.rule == :active_mutation_guard and &1.execute_mutation? == false)
           )
  end

  defp trace_with_logits(trace_suffix, logits) do
    trace_id = "trace-#{trace_suffix}"

    ForwardTrace.new!(
      trace_id: trace_id,
      model_id: "model:fixture",
      signals: [logits_record(trace_id, logits)]
    )
  end

  defp logits_record(trace_id, logits) do
    SignalRecord.new!(
      trace_id: trace_id,
      signal_id: "final_logits:#{trace_id}",
      signal_type: :final_logits,
      model_id: "model:fixture",
      shape: [1, length(logits)],
      tensor_summary: TensorSummary.compute(logits, entropy: true, top_k: 10)
    )
  end

  defp canonical_trace(trace_id, signals, attrs \\ []) do
    struct(
      Crucible.ForwardTrace,
      %{
        trace_id: trace_id,
        provider_kind: :elixir_bumblebee,
        model_id: "hf-internal-testing/tiny-random-gpt2",
        model_family: :gpt2,
        backend: :binary,
        signals: Enum.map(signals, &%{&1 | trace_id: trace_id}),
        capability_report: Keyword.get(attrs, :capability_report)
      }
    )
  end

  defp canonical_signal(signal_type, values, attrs \\ []) do
    %Crucible.SignalRecord{
      signal_id:
        "#{signal_type}:#{Keyword.get(attrs, :token_index, Keyword.get(attrs, :layer_index, "final"))}",
      trace_id: "trace-pending",
      signal_type: signal_type,
      provider_kind: :elixir_bumblebee,
      model_id: "hf-internal-testing/tiny-random-gpt2",
      model_family: :gpt2,
      backend: :binary,
      layer_index: Keyword.get(attrs, :layer_index),
      token_index: Keyword.get(attrs, :token_index),
      tensor_summary: Crucible.TensorSummary.compute(values, entropy: true, top_k: 3),
      metadata: Keyword.get(attrs, :metadata, %{})
    }
  end
end
