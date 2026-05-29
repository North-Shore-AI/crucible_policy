defmodule CruciblePolicy.FixtureTracePolicyTest do
  use ExUnit.Case, async: true

  alias Crucible.CapabilityReport
  alias CruciblePolicy.{EvidenceRef, PolicyPlan}
  alias CrucibleSignalTrace.Ingest

  @fixture_path Path.expand(
                  "../../crucible_signal_trace/test/fixtures/minimal_forward_trace.jsonl",
                  __DIR__
                )

  test "PolicyPlan evaluates ingested fixture trace with evidence refs" do
    trace = Ingest.from_jsonl!(@fixture_path)
    plan = PolicyPlan.new()

    assert {:ok, decision} = PolicyPlan.evaluate(plan, trace)
    assert decision.decision.trace_id == trace.trace_id
    assert decision.selected_target in [:worker, :thinker, :verifier]
    assert [%EvidenceRef{record_id: record_id}] = decision.decision.evidence_refs
    assert record_id == hd(trace.signals).signal_id
    assert is_binary(trace.metadata[:trace_digest])
  end

  test "PolicyPlan handles missing final logits on ingested trace" do
    trace =
      Ingest.from_jsonl!(@fixture_path)
      |> Map.put(:signals, [])

    assert {:ok, decision} = PolicyPlan.evaluate(PolicyPlan.new(), trace)
    assert decision.decision.evidence_refs == []
    assert decision.selected_target == :worker
    assert decision.metadata[:missing_evidence] == []
  end

  test "PolicyPlan surfaces required missing evidence from capability report" do
    trace =
      Ingest.from_jsonl!(@fixture_path)
      |> Map.put(:signals, [])
      |> Map.put(
        :capability_report,
        CapabilityReport.new(
          provider_kind: :fixture,
          model_id: "model:fixture",
          required_missing: [:hidden_state]
        )
      )

    assert {:ok, decision} = PolicyPlan.evaluate(PolicyPlan.new(), trace)

    assert [%{signal_type: :hidden_state, required?: true, impact: :blocks_confidence}] =
             decision.metadata[:missing_evidence]
  end
end
