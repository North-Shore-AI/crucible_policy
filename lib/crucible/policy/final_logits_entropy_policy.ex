defmodule Crucible.Policy.FinalLogitsEntropyPolicy do
  @moduledoc "V4 final-logits entropy replay rule."

  def evaluate(trace, config) do
    with {:ok, signal} <- final_logits(trace),
         entropy when is_number(entropy) <- signal.tensor_summary.entropy do
      status = if entropy <= config.entropy_high_threshold, do: :passed, else: :triggered

      {:ok,
       %{
         policy: :final_logits_entropy_v0,
         status: status,
         action: if(status == :triggered, do: :thinker, else: :worker),
         evidence: %{
           rule: :entropy_limit,
           value: entropy,
           threshold: config.entropy_high_threshold,
           status: status
         }
       }}
    else
      _other ->
        {:skip,
         %{
           policy: :final_logits_entropy_v0,
           reason: :final_logits_unavailable,
           required_signal: :final_logits
         }}
    end
  end

  defp final_logits(%{signals: signals}) do
    case Enum.find(signals, &(&1.signal_type == :final_logits)) do
      nil -> {:error, :missing}
      signal -> {:ok, signal}
    end
  end
end
