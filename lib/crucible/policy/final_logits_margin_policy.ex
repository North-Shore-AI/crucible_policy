defmodule Crucible.Policy.FinalLogitsMarginPolicy do
  @moduledoc "V4 top-1/top-2 margin replay rule."

  def evaluate(trace, config) do
    with {:ok, top_k} <- final_logits_top_k(trace),
         {:ok, margin} <- margin(top_k) do
      status = if margin >= config.margin_low_threshold, do: :passed, else: :triggered

      {:ok,
       %{
         policy: :final_logits_margin_v0,
         status: status,
         action: if(status == :triggered, do: :verifier, else: :worker),
         evidence: %{
           rule: :margin_floor,
           value: margin,
           threshold: config.margin_low_threshold,
           status: status
         }
       }}
    else
      _other ->
        {:skip,
         %{
           policy: :final_logits_margin_v0,
           reason: :top_k_unavailable,
           required_signal: :final_logits
         }}
    end
  end

  defp final_logits_top_k(%{signals: signals}) do
    signals
    |> Enum.find(&(&1.signal_type == :final_logits))
    |> case do
      nil -> {:error, :missing}
      %{tensor_summary: %{top_k: top_k}} when is_list(top_k) -> {:ok, top_k}
      _signal -> {:error, :missing_top_k}
    end
  end

  defp margin([%{logit: first}, %{logit: second} | _rest]), do: {:ok, first - second}
  defp margin([%{"logit" => first}, %{"logit" => second} | _rest]), do: {:ok, first - second}

  defp margin([first, second | _rest]) when is_number(first) and is_number(second),
    do: {:ok, first - second}

  defp margin(_top_k), do: {:error, :insufficient_top_k}
end
