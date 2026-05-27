defmodule CruciblePolicy.PolicyPlan do
  @moduledoc """
  Deterministic first-slice policy thresholds.
  """

  @derive Jason.Encoder
  defstruct policy_ref: "crucible_policy:first_slice",
            high_entropy_threshold: 2.5,
            moderate_entropy_threshold: 1.25,
            worker_confidence: 0.82,
            thinker_confidence: 0.64,
            verifier_confidence: 0.58,
            metadata: %{}

  @type t :: %__MODULE__{}

  def new(attrs \\ []) when is_list(attrs) or is_map(attrs) do
    attrs =
      Map.new(attrs, fn
        {key, value} when is_binary(key) -> {String.to_atom(key), value}
        {key, value} -> {key, value}
      end)

    struct(__MODULE__, attrs)
  end
end
