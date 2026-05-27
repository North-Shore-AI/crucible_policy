defmodule Crucible.Policy.SpilledEnergyPolicy do
  @moduledoc "V5 spilled-energy policy over generation step logits."

  def evaluate(trace, config) do
    steps = signals(trace, :generation_step_logits)

    if steps == [] do
      {:skip,
       %{
         policy: :spilled_energy_v0,
         reason: :generation_step_logits_unavailable,
         required_signal: :generation_step_logits
       }}
    else
      energies = Enum.map(steps, &step_energy/1)
      max_delta = max_delta(energies)
      threshold = config.spilled_energy_threshold
      triggered? = is_number(threshold) and is_number(max_delta) and max_delta > threshold

      {:ok,
       %{
         policy: :spilled_energy_v0,
         status: if(triggered?, do: :triggered, else: :passed),
         action: if(triggered?, do: :verifier, else: :worker),
         evidence: %{
           rule: :spilled_energy_delta,
           energies: energies,
           max_delta: max_delta,
           threshold: threshold
         }
       }}
    end
  end

  defp step_energy(%{metadata: %{energy: energy}}) when is_number(energy), do: energy

  defp step_energy(%{tensor_summary: %{top_k: top_k}}) when is_list(top_k) do
    top_k
    |> Enum.map(&(Map.get(&1, :logit) || Map.get(&1, "logit")))
    |> Enum.reject(&is_nil/1)
    |> logsumexp()
  end

  defp step_energy(_signal), do: nil

  defp logsumexp([]), do: nil

  defp logsumexp(values) do
    max_value = Enum.max(values)

    values
    |> Enum.map(&:math.exp(&1 - max_value))
    |> Enum.sum()
    |> :math.log()
    |> Kernel.+(max_value)
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
