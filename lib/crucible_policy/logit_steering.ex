defmodule CruciblePolicy.LogitSteering do
  @moduledoc """
  Small list-based logits steering helper for tests and logits processors.
  """

  alias CruciblePolicy.SteeringPlan

  def apply(logits, %SteeringPlan{} = plan) when is_list(logits) do
    logits
    |> Enum.with_index()
    |> Enum.map(fn {logit, token_id} ->
      cond do
        token_id in plan.banned_token_ids ->
          :neg_infinity

        true ->
          logit +
            Map.get(plan.token_biases, token_id, Map.get(plan.token_biases, "#{token_id}", 0.0))
      end
    end)
  end
end
