defmodule CruciblePolicy.CrossModelComparisonTest do
  use ExUnit.Case, async: true

  alias Crucible.Policy.CrossModelComparison

  test "compares policy metrics across multiple canonical model traces" do
    traces = [
      canonical_trace("trace:gpt2", "gpt2", [
        signal(:final_logits, [5.0, 1.0, 0.0]),
        signal(:generation_step_logits, [5.0, 1.0, 0.0], token_index: 0),
        signal(:generation_step_logits, [4.0, 2.0, 0.0], token_index: 1)
      ]),
      canonical_trace("trace:distilgpt2", "distilgpt2", [
        signal(:final_logits, [1.0, 0.95, 0.0]),
        signal(:generation_step_logits, [1.0, 0.0, 0.0], token_index: 0),
        signal(:generation_step_logits, [0.0, 1.0, 0.0], token_index: 1)
      ])
    ]

    report = CrossModelComparison.compare(traces)

    assert report.schema == "crucible.policy.cross_model_comparison.v1"
    assert report.status == :ok
    assert report.trace_count == 2
    assert report.model_count == 2
    assert report.metrics.entropy.count == 2
    assert report.metrics.margin.count == 2
    assert report.metrics.top_k_stability.count == 2
    assert report.metrics.margin.overall.max_delta > 0.0
    assert report.skipped == []
  end

  test "records structured blocker when fewer than two models are available" do
    report =
      CrossModelComparison.compare([
        canonical_trace("trace:single", "gpt2", [signal(:final_logits, [5.0, 1.0, 0.0])])
      ])

    assert report.status == :insufficient_models
    assert [%{reason: :insufficient_models, required_model_count: 2}] = report.skipped
  end

  defp canonical_trace(trace_id, model_id, signals) do
    %Crucible.ForwardTrace{
      trace_id: trace_id,
      provider_kind: :elixir_bumblebee,
      model_id: model_id,
      model_family: :gpt2,
      backend: :binary,
      signals: Enum.map(signals, &%{&1 | trace_id: trace_id, model_id: model_id})
    }
  end

  defp signal(signal_type, values, attrs \\ []) do
    %Crucible.SignalRecord{
      signal_id: "#{signal_type}:#{Keyword.get(attrs, :token_index, "final")}",
      trace_id: "trace:pending",
      signal_type: signal_type,
      provider_kind: :elixir_bumblebee,
      model_id: "pending",
      model_family: :gpt2,
      backend: :binary,
      token_index: Keyword.get(attrs, :token_index),
      tensor_summary: Crucible.TensorSummary.compute(values, entropy: true, top_k: 3)
    }
  end
end
