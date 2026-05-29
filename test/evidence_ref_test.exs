defmodule CruciblePolicy.EvidenceRefTest do
  use ExUnit.Case, async: true

  alias Crucible.{CapabilityReport, ForwardTrace, SignalRecord}
  alias CruciblePolicy.{Evidence, EvidenceRef}

  test "EvidenceRef roundtrips through JSON" do
    ref =
      EvidenceRef.from_signal(
        SignalRecord.new!(
          signal_id: "sig-1",
          trace_id: "trace-1",
          signal_type: :final_logits,
          model_id: "model:fixture"
        )
      )

    decoded = ref |> Jason.encode!() |> Jason.decode!()

    assert decoded["kind"] == "signal_record"
    assert decoded["record_id"] == "sig-1"
    assert decoded["signal_type"] == "final_logits"
  end

  test "Evidence extracts missing and degraded entries from capability report" do
    trace =
      ForwardTrace.new!(
        trace_id: "trace-evidence",
        model_id: "model:fixture",
        capability_report:
          CapabilityReport.new(
            required_missing: [:hidden_state],
            optional_dropped: [:attention_weights],
            degraded: [%{capability: :generation_step_logits, reason: :summary_only}]
          )
      )

    assert [%{signal_type: :hidden_state}] = Evidence.missing_entries(trace)

    assert Enum.any?(Evidence.degraded_entries(trace), fn entry ->
             entry.signal_type in [:generation_step_logits, :attention_weights]
           end)
  end
end
