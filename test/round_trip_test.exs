defmodule CruciblePolicy.RoundTripTest do
  use ExUnit.Case, async: true

  alias CruciblePolicy.{
    ControlVector,
    FusionDecision,
    GateDecision,
    RouteDecision,
    SharedMemoryWrite,
    SteeringPlan,
    VerifierDecision,
    VerifierSignal
  }

  test "decision contracts encode and decode through JSON maps" do
    contracts = [
      RouteDecision.new!(trace_id: "trace-1", selected_target: :worker),
      GateDecision.new!(trace_id: "trace-1", action: :continue),
      FusionDecision.new!(trace_id: "trace-1", fusion_mode: :weighted_logits),
      SteeringPlan.new!(trace_id: "trace-1", token_biases: %{1 => 0.5}),
      VerifierDecision.new!(trace_id: "trace-1", verifier_ref: "verifier", score: 0.9),
      %VerifierSignal{verifier_ref: "verifier", trace_id: "trace-1", score: 0.9, passed?: true},
      ControlVector.new!(vector_id: "cv", trace_id: "trace-1"),
      SharedMemoryWrite.new!(memory_ref: "mem", trace_id: "trace-1")
    ]

    for contract <- contracts do
      assert {:ok, json} = Jason.encode(contract)
      assert {:ok, decoded} = Jason.decode(json)
      assert is_map(decoded)
    end
  end
end
