defmodule Crucible.Policy.CrossModelComparison do
  @moduledoc """
  Cross-model policy comparison over canonical Crucible traces.

  The comparison is intentionally bounded: it evaluates each trace through the
  existing policy ladder, extracts scalar policy evidence, and reports per-model
  distributions without copying tensor values into the report.
  """

  alias Crucible.ForwardTrace
  alias Crucible.Policy.{PolicyConfig, PolicyPlan}

  @schema "crucible.policy.cross_model_comparison.v1"
  @metrics [
    :entropy,
    :margin,
    :top_k_stability,
    :spilled_energy_delta,
    :hidden_state_norm_drift,
    :trajectory_entropy_drift
  ]

  @type t :: %{
          schema: String.t(),
          status: :ok | :insufficient_models,
          trace_count: non_neg_integer(),
          model_count: non_neg_integer(),
          rows: [map()],
          metrics: map(),
          skipped: [map()]
        }

  @spec compare([ForwardTrace.t()], PolicyConfig.t()) :: t()
  def compare(traces, %PolicyConfig{} = config \\ %PolicyConfig{}) when is_list(traces) do
    rows = Enum.map(traces, &row(&1, PolicyPlan.evaluate(&1, config)))
    model_count = model_count(rows)

    %{
      schema: @schema,
      status: if(model_count >= 2, do: :ok, else: :insufficient_models),
      trace_count: length(rows),
      model_count: model_count,
      rows: rows,
      metrics: metric_distributions(rows),
      skipped: skipped(model_count)
    }
  end

  defp row(%ForwardTrace{} = trace, decision) do
    %{
      trace_id: trace.trace_id,
      model_id: trace.model_id,
      model_family: trace.model_family,
      provider_kind: trace.provider_kind,
      backend: trace.backend,
      selected_policy: decision.selected_policy,
      selected_action: decision.selected_action,
      entropy: evidence_value(decision, :entropy_limit, :value) || signal_entropy(trace),
      margin: evidence_value(decision, :margin_floor, :value) || final_logits_margin(trace),
      top_k_stability: evidence_value(decision, :top_k_stability_floor, :value),
      spilled_energy_delta: evidence_value(decision, :spilled_energy_delta, :max_delta),
      hidden_state_norm_drift: evidence_value(decision, :hidden_state_norm_drift, :value),
      trajectory_entropy_drift: evidence_value(decision, :trajectory_entropy_drift, :value),
      skipped_policies: decision.skipped_policies
    }
  end

  defp evidence_value(decision, rule, field) do
    decision.evidence
    |> Enum.find(&(Map.get(&1, :rule) == rule))
    |> case do
      nil -> nil
      evidence -> Map.get(evidence, field)
    end
  end

  defp signal_entropy(%ForwardTrace{} = trace) do
    trace
    |> signal(:final_logits)
    |> case do
      %{tensor_summary: %{entropy: entropy}} when is_number(entropy) -> entropy
      _signal -> nil
    end
  end

  defp final_logits_margin(%ForwardTrace{} = trace) do
    with %{tensor_summary: %{top_k: top_k}} when is_list(top_k) <- signal(trace, :final_logits),
         [first, second | _rest] <- top_k,
         first_logit when is_number(first_logit) <- logit(first),
         second_logit when is_number(second_logit) <- logit(second) do
      first_logit - second_logit
    else
      _other -> nil
    end
  end

  defp signal(%ForwardTrace{} = trace, signal_type),
    do: Enum.find(trace.signals, &(&1.signal_type == signal_type))

  defp logit(%{logit: value}), do: value
  defp logit(value) when is_number(value), do: value
  defp logit(_value), do: nil

  defp metric_distributions(rows) do
    Map.new(@metrics, fn metric ->
      values =
        rows
        |> Enum.map(&{model_key(&1), Map.get(&1, metric)})
        |> Enum.filter(fn {_model, value} -> is_number(value) end)

      {metric,
       %{
         count: length(values),
         by_model:
           values
           |> Enum.group_by(fn {model, _value} -> model end, fn {_model, value} -> value end)
           |> Map.new(fn {model, model_values} -> {model, stats(model_values)} end),
         overall: stats(Enum.map(values, fn {_model, value} -> value end))
       }}
    end)
  end

  defp stats([]), do: %{count: 0, min: nil, max: nil, mean: nil, max_delta: nil}

  defp stats(values) do
    min = Enum.min(values)
    max = Enum.max(values)

    %{
      count: length(values),
      min: min,
      max: max,
      mean: Enum.sum(values) / length(values),
      max_delta: max - min
    }
  end

  defp model_count(rows) do
    rows
    |> Enum.map(&model_key/1)
    |> MapSet.new()
    |> MapSet.size()
  end

  defp model_key(%{model_id: model_id}) when is_binary(model_id), do: model_id
  defp model_key(%{trace_id: trace_id}) when is_binary(trace_id), do: "unknown:#{trace_id}"
  defp model_key(_row), do: "unknown"

  defp skipped(model_count) when model_count >= 2, do: []

  defp skipped(_model_count) do
    [
      %{
        check: :cross_model_distribution,
        reason: :insufficient_models,
        required_model_count: 2
      }
    ]
  end
end
