defmodule Crucible.Policy.HiddenStateNormDriftPolicy do
  @moduledoc "V5 hidden-state norm drift policy."

  def evaluate(trace, config) do
    hidden_states = signals(trace, :hidden_state)

    if length(hidden_states) < 2 do
      {:skip,
       %{
         policy: :hidden_state_norm_drift_v0,
         reason: :hidden_states_unavailable,
         required_signal: :hidden_state
       }}
    else
      max_delta = hidden_states |> Enum.map(& &1.tensor_summary.norm_l2) |> max_delta()
      triggered? = is_number(max_delta) and max_delta > config.hidden_norm_drift_threshold

      {:ok,
       %{
         policy: :hidden_state_norm_drift_v0,
         status: if(triggered?, do: :triggered, else: :passed),
         action: if(triggered?, do: :verifier, else: :worker),
         evidence: %{
           rule: :hidden_state_norm_drift,
           value: max_delta,
           threshold: config.hidden_norm_drift_threshold,
           count: length(hidden_states)
         }
       }}
    end
  end

  defp max_delta(values) do
    values
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [left, right] -> abs(right - left) end)
    |> case do
      [] -> nil
      deltas -> Enum.max(deltas)
    end
  end

  defp signals(trace, signal_type),
    do: Enum.filter(trace.signals, &(&1.signal_type == signal_type))
end
