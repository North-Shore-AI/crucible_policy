defmodule CruciblePolicy.LogitSteering do
  @moduledoc """
  Small list-based logits steering helper for tests and logits processors.
  """

  alias CruciblePolicy.SteeringPlan

  def apply(logits, %SteeringPlan{} = plan) when is_list(logits) do
    SteeringPlan.fuse(plan, logits)
  end
end
