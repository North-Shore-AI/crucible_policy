defmodule CruciblePolicy.VerifierDecisionTest do
  use ExUnit.Case, async: true

  alias Crucible.CapabilityReport
  alias CruciblePolicy.VerifierDecision
  alias CrucibleSignalTrace.Ingest

  @fixture Path.expand(
             "../../crucible_signal_trace/test/fixtures/replay_token_step_trace.jsonl",
             __DIR__
           )

  test "VerifierDecision constructs and roundtrips with evidence refs" do
    trace = Ingest.from_jsonl!(@fixture)

    decision = VerifierDecision.from_trace(trace, verifier_ref: "verifier:fixture")

    assert decision.passed?
    assert decision.score == 0.86
    assert decision.confidence_band == :high
    assert decision.decision.decision_type == :verifier
    assert decision.decision.evidence_refs == decision.evidence_refs

    decoded = decision |> Jason.encode!() |> Jason.decode!()
    assert decoded["verifier_ref"] == "verifier:fixture"
    assert [%{"record_id" => "sig-token-step-final"}] = decoded["evidence_refs"]
  end

  test "missing required evidence blocks verifier pass and lowers confidence" do
    trace =
      @fixture
      |> Ingest.from_jsonl!()
      |> Map.put(:signals, [])
      |> Map.put(
        :capability_report,
        CapabilityReport.new(
          provider_kind: :fixture,
          model_id: "model:fixture",
          required_missing: [:hidden_state]
        )
      )

    decision = VerifierDecision.from_trace(trace, verifier_ref: "verifier:fixture", score: 0.95)

    refute decision.passed?
    assert decision.confidence_band == :low
    assert decision.score == 0.34
    assert [%{signal_type: :hidden_state}] = decision.metadata.missing_evidence
  end

  test "external constructor keys do not create arbitrary atoms" do
    external_key = "external_key_#{System.unique_integer([:positive])}"

    refute existing_atom?(external_key)

    decision =
      VerifierDecision.new!(%{
        "trace_id" => "trace-external",
        "verifier_ref" => "verifier:fixture",
        "score" => 0.9,
        "metadata" => %{external_key => "kept-as-string"}
      })

    assert decision.metadata[external_key] == "kept-as-string"
    refute existing_atom?(external_key)
  end

  defp existing_atom?(value) do
    _ = String.to_existing_atom(value)
    true
  rescue
    ArgumentError -> false
  end
end
