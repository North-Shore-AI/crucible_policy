defmodule Crucible.Policy.TopKStabilityPolicy do
  @moduledoc "Top-k stability policy over generation step logits."

  def evaluate(trace, config) do
    steps = signals(trace, :generation_step_logits)

    if length(steps) < 2 do
      {:skip,
       %{
         policy: :top_k_stability_v0,
         reason: :generation_step_logits_unavailable,
         required_signal: :generation_step_logits
       }}
    else
      stability = average_pairwise_jaccard(steps)
      status = if stability < config.top_k_stability_threshold, do: :triggered, else: :passed

      {:ok,
       %{
         policy: :top_k_stability_v0,
         status: status,
         action: if(status == :triggered, do: :verifier, else: :worker),
         evidence: %{
           rule: :top_k_stability_floor,
           value: stability,
           threshold: config.top_k_stability_threshold,
           steps: length(steps)
         }
       }}
    end
  end

  defp average_pairwise_jaccard(steps) do
    steps
    |> Enum.map(&token_set/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [left, right] -> jaccard(left, right) end)
    |> then(&(Enum.sum(&1) / length(&1)))
  end

  defp token_set(signal) do
    signal.tensor_summary
    |> Map.get(:top_k, [])
    |> Enum.map(&Map.get(&1, :token_id))
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp jaccard(left, right) do
    union = MapSet.union(left, right) |> MapSet.size()

    if union == 0 do
      0.0
    else
      intersection = MapSet.intersection(left, right) |> MapSet.size()
      intersection / union
    end
  end

  defp signals(trace, signal_type),
    do: Enum.filter(trace.signals, &(&1.signal_type == signal_type))
end
