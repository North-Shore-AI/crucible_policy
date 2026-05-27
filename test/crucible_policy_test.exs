defmodule CruciblePolicyTest do
  use ExUnit.Case
  doctest CruciblePolicy

  alias CruciblePolicy.{
    ControlVector,
    FusionDecision,
    GateDecision,
    LogitSteering,
    RouteDecision,
    SharedMemoryWrite,
    SteeringPlan,
    Uncertainty,
    VerifierSignal
  }

  alias CrucibleSignal.{SignalRef, TensorSummary}
  alias CrucibleSignalTrace.{ForwardTrace, SignalRecord}

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

  test "deterministic policy selects verifier for high entropy" do
    trace = trace_with_logits("verifier", List.duplicate(0.0, 24))

    assert {:ok, decision} = CruciblePolicy.decide(trace)
    assert decision.selected_target == :verifier
    assert decision.decision.uncertainty.entropy > 2.5
  end

  test "uncertainty captures nonfinite and trajectory drift components" do
    trace =
      ForwardTrace.new!(
        trace_id: "trace-uncertainty",
        model_ref: "model",
        layer_trajectory: [%{layer_index: 1, drift: 0.3}, %{layer_index: 2, drift: 0.9}],
        signal_records: [
          SignalRecord.new!(
            signal_ref: signal_ref("bad", :final_logits),
            summary: %{
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
    assert uncertainty.nan_or_inf
    assert Uncertainty.high?(uncertainty)
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

    vector = %ControlVector{vector_id: "cv", trace_id: "trace-1", shape: [1, 4], dtype: :f32}
    memory = %SharedMemoryWrite{memory_ref: "mem", trace_id: "trace-1", signal_refs: ["sig"]}

    assert gate.action == :verify
    assert fusion.fusion_mode == :weighted_logits
    assert verifier.passed?
    assert vector.shape == [1, 4]
    assert memory.retention == :ephemeral
  end

  test "steering plan can bias and ban logits" do
    plan =
      SteeringPlan.new!(
        trace_id: "trace-1",
        token_biases: %{1 => 1.5, "2" => -0.5},
        banned_token_ids: [0]
      )

    assert LogitSteering.apply([1.0, 1.0, 1.0], plan) == [:neg_infinity, 2.5, 0.5]
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
      model_ref: "qwen3:fixture",
      signal_records: [
        SignalRecord.new!(
          signal_ref: signal_ref(trace_id, :final_logits),
          summary: TensorSummary.summarize(logits, entropy: true)
        )
      ]
    )
  end

  defp signal_ref(trace_id, signal_type) do
    SignalRef.new!(
      trace_id: trace_id,
      signal_id: "#{signal_type}:0",
      signal_type: signal_type,
      model_ref: "qwen3:fixture",
      dtype: :f32,
      shape: {1, 3}
    )
  end
end
