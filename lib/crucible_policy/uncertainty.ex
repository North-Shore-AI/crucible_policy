defmodule CruciblePolicy.Uncertainty do
  @moduledoc """
  Structured uncertainty components derived from signal traces.
  """

  alias CrucibleSignalTrace.{ForwardTrace, LayerTrajectory, SignalRecord}

  @derive Jason.Encoder
  defstruct token_entropy: nil,
            trace_entropy: nil,
            entropy: nil,
            margin: nil,
            layer_drift: nil,
            moe_router_entropy: nil,
            logit_lens_trajectory_stability: nil,
            intra_model_logit_lens_kl: nil,
            inter_model_disagreement: nil,
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
    trace_entropy = summary_field(logits_summary, :entropy)

    %__MODULE__{
      trace_entropy: trace_entropy,
      entropy: trace_entropy,
      margin: Map.get(trace.metadata, :logit_margin) || summary_margin(logits_summary),
      layer_drift: trajectory_drift,
      moe_router_entropy: signal_entropy(trace, :moe_router_logits),
      logit_lens_trajectory_stability: logit_lens_stability(trace),
      intra_model_logit_lens_kl:
        Map.get(trace.metadata, :intra_model_logit_lens_kl) ||
          intra_model_kl(trace, trace_entropy),
      inter_model_disagreement:
        Keyword.get(opts, :inter_model_disagreement) ||
          Map.get(trace.metadata, :inter_model_disagreement),
      attention_diffusion: Map.get(trace.metadata, :attention_diffusion),
      norm_anomaly: truthy?(Map.get(trace.metadata, :norm_anomaly)),
      nan_or_inf: summary_nonfinite?(logits_summary),
      cache_discontinuity: truthy?(Map.get(trace.metadata, :cache_discontinuity)),
      policy_confidence: Keyword.get(opts, :policy_confidence),
      metadata: %{}
    }
  end

  def from_signal(%SignalRecord{} = record, %__MODULE__{} = prior \\ %__MODULE__{}) do
    entropy = summary_field(record.summary, :entropy)
    signal_type = record.signal_ref.signal_type

    prior
    |> maybe_put(:token_entropy, entropy)
    |> maybe_put(:entropy, entropy)
    |> maybe_put(:moe_router_entropy, if(signal_type == :moe_router_logits, do: entropy))
    |> maybe_put(
      :intra_model_logit_lens_kl,
      Map.get(record.metadata, :intra_model_logit_lens_kl)
    )
    |> maybe_put(:layer_drift, Map.get(record.metadata, :layer_drift))
    |> maybe_put(
      :logit_lens_trajectory_stability,
      Map.get(record.metadata, :trajectory_stability)
    )
    |> maybe_put(:policy_confidence, Map.get(record.metadata, :policy_confidence))
  end

  def combine(uncertainties) when is_list(uncertainties) do
    Enum.reduce(uncertainties, %__MODULE__{}, fn uncertainty, acc ->
      %__MODULE__{
        acc
        | token_entropy: max_number(acc.token_entropy, uncertainty.token_entropy),
          trace_entropy: max_number(acc.trace_entropy, uncertainty.trace_entropy),
          entropy: max_number(acc.entropy, uncertainty.entropy),
          margin: min_number(acc.margin, uncertainty.margin),
          layer_drift: max_number(acc.layer_drift, uncertainty.layer_drift),
          moe_router_entropy: max_number(acc.moe_router_entropy, uncertainty.moe_router_entropy),
          logit_lens_trajectory_stability:
            min_number(
              acc.logit_lens_trajectory_stability,
              uncertainty.logit_lens_trajectory_stability
            ),
          intra_model_logit_lens_kl:
            max_number(acc.intra_model_logit_lens_kl, uncertainty.intra_model_logit_lens_kl),
          inter_model_disagreement:
            max_number(acc.inter_model_disagreement, uncertainty.inter_model_disagreement),
          attention_diffusion:
            max_number(acc.attention_diffusion, uncertainty.attention_diffusion),
          norm_anomaly: acc.norm_anomaly or uncertainty.norm_anomaly,
          nan_or_inf: acc.nan_or_inf or uncertainty.nan_or_inf,
          cache_discontinuity: acc.cache_discontinuity or uncertainty.cache_discontinuity,
          policy_confidence: uncertainty.policy_confidence || acc.policy_confidence
      }
    end)
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

  defp summary_margin(nil), do: nil

  defp summary_margin(summary) do
    case Map.get(summary, :top_k, []) do
      [first, second | _rest] -> first - second
      _other -> nil
    end
  end

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

  defp signal_entropy(%ForwardTrace{} = trace, signal_type) do
    trace.signal_records
    |> Enum.find(fn record -> record.signal_ref.signal_type == signal_type end)
    |> case do
      nil -> nil
      record -> summary_field(record.summary, :entropy)
    end
  end

  defp logit_lens_stability(%ForwardTrace{
         metadata: %{logit_lens_trajectory_stability: stability}
       })
       when is_number(stability),
       do: stability

  defp logit_lens_stability(%ForwardTrace{layer_trajectory: %LayerTrajectory{} = trajectory}) do
    case LayerTrajectory.cosine_drifts(trajectory) do
      {:ok, []} ->
        nil

      {:ok, drifts} ->
        max_drift = drifts |> Enum.map(& &1.distance) |> Enum.max()
        max(0.0, 1.0 - max_drift)

      {:error, _reason} ->
        nil
    end
  end

  defp logit_lens_stability(_trace), do: nil

  defp intra_model_kl(%ForwardTrace{} = trace, final_entropy) when is_number(final_entropy) do
    trace.signal_records
    |> Enum.filter(fn record -> record.signal_ref.signal_type == :logit_lens_intermediate end)
    |> Enum.map(fn record -> summary_field(record.summary, :entropy) end)
    |> Enum.filter(&is_number/1)
    |> Enum.map(&abs(&1 - final_entropy))
    |> case do
      [] -> nil
      deltas -> Enum.max(deltas)
    end
  end

  defp intra_model_kl(_trace, _final_entropy), do: nil

  defp maybe_put(%__MODULE__{} = uncertainty, _field, nil), do: uncertainty

  defp maybe_put(%__MODULE__{} = uncertainty, field, value),
    do: Map.put(uncertainty, field, value)

  defp max_number(nil, value), do: value
  defp max_number(value, nil), do: value
  defp max_number(left, right), do: max(left, right)

  defp min_number(nil, value), do: value
  defp min_number(value, nil), do: value
  defp min_number(left, right), do: min(left, right)

  defp truthy?(value), do: value in [true, "true", 1]
end
