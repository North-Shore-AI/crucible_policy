defmodule CruciblePolicy.Uncertainty do
  @moduledoc """
  Structured uncertainty components derived from signal traces.
  """

  alias CrucibleSignalTrace.ForwardTrace

  @derive Jason.Encoder
  defstruct entropy: nil,
            margin: nil,
            layer_drift: nil,
            attention_diffusion: nil,
            norm_anomaly: false,
            nan_or_inf: false,
            cache_discontinuity: false,
            policy_confidence: nil,
            metadata: %{}

  @type t :: %__MODULE__{}

  def from_trace(%ForwardTrace{} = trace, opts \\ []) do
    logits_summary = final_logits_summary(trace)
    trajectory_drift = trajectory_drift(trace)

    %__MODULE__{
      entropy: summary_field(logits_summary, :entropy),
      margin: Map.get(trace.metadata, :logit_margin),
      layer_drift: trajectory_drift,
      attention_diffusion: Map.get(trace.metadata, :attention_diffusion),
      norm_anomaly: truthy?(Map.get(trace.metadata, :norm_anomaly)),
      nan_or_inf: summary_nonfinite?(logits_summary),
      cache_discontinuity: truthy?(Map.get(trace.metadata, :cache_discontinuity)),
      policy_confidence: Keyword.get(opts, :policy_confidence),
      metadata: %{}
    }
  end

  def high?(%__MODULE__{} = uncertainty, threshold \\ 2.5) do
    truthy?(uncertainty.nan_or_inf) or truthy?(uncertainty.norm_anomaly) or
      truthy?(uncertainty.cache_discontinuity) or
      (is_number(uncertainty.entropy) and uncertainty.entropy >= threshold)
  end

  defp final_logits_summary(%ForwardTrace{} = trace) do
    trace.signal_records
    |> Enum.find(fn record -> record.signal_ref.signal_type == :final_logits end)
    |> case do
      nil -> nil
      record -> record.summary
    end
  end

  defp summary_field(nil, _field), do: nil
  defp summary_field(summary, field), do: Map.get(summary, field)

  defp summary_nonfinite?(nil), do: false

  defp summary_nonfinite?(summary) do
    Map.get(summary, :nan_count, 0) > 0 or
      Map.get(summary, :positive_infinity_count, 0) > 0 or
      Map.get(summary, :negative_infinity_count, 0) > 0
  end

  defp trajectory_drift(%ForwardTrace{layer_trajectory: nil}), do: nil

  defp trajectory_drift(%ForwardTrace{layer_trajectory: trajectory}) do
    trajectory.points
    |> Enum.map(&Map.get(&1, :drift))
    |> Enum.filter(&is_number/1)
    |> case do
      [] -> nil
      drifts -> Enum.max(drifts)
    end
  end

  defp truthy?(value), do: value in [true, "true", 1]
end
