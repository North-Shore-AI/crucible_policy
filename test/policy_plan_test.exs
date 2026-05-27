defmodule CruciblePolicy.PolicyPlanTest do
  use ExUnit.Case, async: true

  alias CruciblePolicy.{DecisionContext, PolicyPlan, RouteDecision, SteeringPlan}
  alias CrucibleSignal.{SignalRef, TensorSummary}
  alias CrucibleSignalTrace.{ForwardTrace, SignalRecord}

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
        model_ref: "model:fixture",
        layer_trajectory: [
          %{layer_index: 12, vector: [1.0, 0.0]},
          %{layer_index: 16, vector: [-1.0, 0.0]}
        ],
        signal_records: [
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

    fragment = %{signal_records: [logits_record("trace-fragment", List.duplicate(0.0, 24))]}

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

  defp trace_with_logits(trace_suffix, logits) do
    trace_id = "trace-#{trace_suffix}"

    ForwardTrace.new!(
      trace_id: trace_id,
      model_ref: "model:fixture",
      signal_records: [logits_record(trace_id, logits)]
    )
  end

  defp logits_record(trace_id, logits) do
    SignalRecord.new!(
      signal_ref:
        SignalRef.for_final_logits(
          trace_id: trace_id,
          signal_id: "final_logits:#{trace_id}",
          model_ref: "model:fixture",
          shape: {1, length(logits)}
        ),
      summary: TensorSummary.summarize(logits, entropy: true)
    )
  end
end
