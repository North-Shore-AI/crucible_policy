defmodule CruciblePolicyTest do
  use ExUnit.Case
  doctest CruciblePolicy

  alias CruciblePolicy.{
    ControlVector,
    DecisionContext,
    FusionDecision,
    GateDecision,
    LogitSteering,
    PolicyPlan,
    RouteDecision,
    RunningScalar,
    SharedMemoryWrite,
    SteeringPlan,
    Uncertainty,
    VerifierSignal
  }

  alias Crucible.{ForwardTrace, SignalRecord, TensorSummary}
  alias CrucibleSignalTrace.LayerTrajectory

  test "exposes package version" do
    assert CruciblePolicy.version() == "0.1.0"
  end

  test "deterministic policy selects worker for low uncertainty" do
    trace = trace_with_logits("worker", [10.0, 0.0, -1.0])

    assert {:ok, %RouteDecision{} = decision} = CruciblePolicy.decide(trace)
    assert decision.selected_target == :worker
    assert decision.decision.confidence == 0.82
    assert decision.decision.uncertainty.entropy < 1.0
  end

  test "deterministic policy selects thinker for planning metadata" do
    trace =
      "thinker"
      |> trace_with_logits([8.0, 1.0, 0.0])
      |> then(&%{&1 | metadata: Map.put(&1.metadata, :task_type, :planning)})

    assert {:ok, decision} = CruciblePolicy.decide(trace)
    assert decision.selected_target == :thinker
  end

  test "deterministic policy selects thinker for high entropy" do
    trace = trace_with_logits("thinker-high-entropy", List.duplicate(0.0, 24))

    assert {:ok, decision} = CruciblePolicy.decide(trace)
    assert decision.selected_target == :thinker
    assert decision.decision.uncertainty.entropy > 2.5
  end

  test "deterministic policy selects verifier for low output margin" do
    trace = trace_with_logits("verifier-margin", [1.0, 0.96, 0.0])

    assert {:ok, decision} = CruciblePolicy.decide(trace)
    assert decision.selected_target == :verifier
    assert decision.decision.uncertainty.margin < 0.15
  end

  test "uncertainty captures nonfinite and trajectory drift components" do
    trace =
      ForwardTrace.new!(
        trace_id: "trace-uncertainty",
        model_id: "model",
        layer_trajectory:
          LayerTrajectory.new!([
            %{layer_index: 1, drift: 0.3},
            %{layer_index: 2, drift: 0.9}
          ]),
        signals: [
          SignalRecord.new!(
            trace_id: "trace-uncertainty",
            signal_id: "final_logits:bad",
            signal_type: :final_logits,
            model_id: "model",
            tensor_summary: %{
              entropy: 0.2,
              nan_count: 1,
              positive_infinity_count: 0,
              negative_infinity_count: 0
            }
          )
        ]
      )

    uncertainty = Uncertainty.from_trace(trace)

    assert uncertainty.layer_drift == 0.9
    assert uncertainty.trace_entropy == 0.2
    assert uncertainty.nan_or_inf
    assert Uncertainty.high?(uncertainty)
  end

  test "running scalar tracks token entropy incrementally" do
    scalar = RunningScalar.from_values([1.0, 2.0, 3.0])

    assert scalar.count == 3
    assert scalar.mean == 2.0
    assert scalar.variance == 2 / 3
    assert scalar.min == 1.0
    assert scalar.max == 3.0
  end

  test "policy plan evaluates token-boundary signal records" do
    plan = PolicyPlan.new(high_entropy_threshold: 10.0, steering_entropy_threshold: 1.0)

    context =
      DecisionContext.new(
        trace_id: "trace-incremental",
        runtime_profile: %{model_id: "model:fixture"}
      )

    record = logits_record("trace-incremental", [0.0, 0.0, 0.0], token_index: 4)

    assert {:steer, %SteeringPlan{} = steering, next_context} =
             PolicyPlan.evaluate_signal(plan, record, context)

    assert steering.mode == :token_boundary
    assert next_context.token_index == 4
    assert next_context.running_entropy.count == 1
  end

  test "in-graph steering fails closed without surface capability" do
    plan =
      SteeringPlan.new!(
        trace_id: "trace-steer",
        mode: :in_graph,
        energies: [%{source: :policy_rule, kind: :safety, energy: 1.0, weight: 1.0}]
      )

    context = DecisionContext.new(surface_id: "surface:fixture")

    assert SteeringPlan.validate_surface(plan, context) == {:error, :steering_surface_unavailable}

    capable =
      DecisionContext.new(
        surface_id: "surface:fixture",
        metadata: %{capabilities: [:in_graph_steering]}
      )

    assert SteeringPlan.validate_surface(plan, capable) == :ok
  end

  test "builds gate, fusion, verifier, control vector, and memory contracts" do
    gate = GateDecision.new!(trace_id: "trace-1", action: :verify, reason: :high_entropy)

    fusion =
      FusionDecision.new!(
        trace_id: "trace-1",
        fusion_mode: :weighted_logits,
        input_refs: ["a", "b"],
        weights: %{"a" => 0.7, "b" => 0.3}
      )

    verifier = %VerifierSignal{
      verifier_ref: "verifier",
      trace_id: "trace-1",
      score: 0.8,
      passed?: true
    }

    vector = ControlVector.new!(vector_id: "cv", trace_id: "trace-1", shape: [1, 4], dtype: :f32)
    memory = SharedMemoryWrite.new!(memory_ref: "mem", trace_id: "trace-1", signal_refs: ["sig"])

    assert gate.action == :verify
    assert fusion.fusion_mode == :weighted_logits
    assert verifier.passed?
    assert vector.shape == [1, 4]
    assert memory.retention == :ephemeral
  end

  test "active-control handoff requires negotiated capabilities" do
    vector = ControlVector.new!(vector_id: "cv", trace_id: "trace-1", target_tap: "residual:12")
    memory = SharedMemoryWrite.new!(memory_ref: "mem", trace_id: "trace-1")

    assert {:ok, %{action: :active_control_handoff}} = ControlVector.handoff(vector, [:inject])

    assert {:error, %GateDecision{reason: :unsupported_active_control}} =
             ControlVector.handoff(vector, [])

    assert {:ok, %{action: :memory_write_handoff}} =
             SharedMemoryWrite.handoff(memory, [:shared_memory])

    assert {:error, %GateDecision{reason: :unsupported_active_control}} =
             SharedMemoryWrite.handoff(memory, [])
  end

  test "steering plan can bias, penalize, and ban logits" do
    plan =
      SteeringPlan.new!(
        trace_id: "trace-1",
        token_biases: %{1 => 1.5, "2" => -0.5},
        banned_token_ids: [0],
        energies: [
          %{source: :policy_rule, kind: :safety, energy: %{1 => 0.2, "2" => 0.5}, weight: 2.0}
        ]
      )

    assert LogitSteering.apply([1.0, 1.0, 1.0], plan) == [:neg_infinity, 2.1, -0.5]
  end

  test "encodes route decisions to JSON" do
    trace = trace_with_logits("json", [10.0, 0.0])
    {:ok, decision} = CruciblePolicy.decide(trace)

    assert {:ok, json} = Jason.encode(decision)
    assert {:ok, decoded} = Jason.decode(json)
    assert decoded["selected_target"] == "worker"
  end

  defp trace_with_logits(trace_suffix, logits) do
    trace_id = "trace-#{trace_suffix}"

    ForwardTrace.new!(
      trace_id: trace_id,
      model_id: "model:fixture",
      signals: [
        logits_record(trace_id, logits)
      ]
    )
  end

  defp logits_record(trace_id, logits, opts \\ []) do
    SignalRecord.new!(
      [
        trace_id: trace_id,
        signal_id: "final_logits:#{trace_id}",
        signal_type: :final_logits,
        model_id: "model:fixture",
        dtype: :f32,
        shape: [1, length(logits)],
        token_index: Keyword.get(opts, :token_index),
        tensor_summary: TensorSummary.compute(logits, entropy: true, top_k: 10)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    )
  end
end
