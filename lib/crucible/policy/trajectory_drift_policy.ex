defmodule Crucible.Policy.TrajectoryDriftPolicy do
  @moduledoc "V5 trajectory drift policy over intermediate/logit-lens summaries."

  @trajectory_signals [:intermediate_logits, :logit_lens_projection, :logit_lens_intermediate]

  def evaluate(trace, config) do
    points = Enum.filter(trace.signals, &(&1.signal_type in @trajectory_signals))

    if length(points) < 2 do
      {:skip,
       %{
         policy: :trajectory_drift_v1,
         reason: :intermediate_logits_unavailable,
         required_signal: :intermediate_logits
       }}
    else
      drift = points |> Enum.map(& &1.tensor_summary.entropy) |> max_delta()
      triggered? = is_number(drift) and drift > config.trajectory_drift_threshold

      {:ok,
       %{
         policy: :trajectory_drift_v1,
         status: if(triggered?, do: :triggered, else: :passed),
         action: if(triggered?, do: :verifier, else: :worker),
         evidence: %{
           rule: :trajectory_entropy_drift,
           value: drift,
           threshold: config.trajectory_drift_threshold,
           count: length(points)
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
end
