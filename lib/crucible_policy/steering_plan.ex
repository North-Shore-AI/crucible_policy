defmodule CruciblePolicy.SteeringPlan do
  @moduledoc """
  Decode steering plan, initially consumed by logits processors.
  """

  alias CruciblePolicy.Decision

  @derive Jason.Encoder
  defstruct decision: nil,
            token_biases: %{},
            temperature: nil,
            banned_token_ids: [],
            metadata: %{}

  @type t :: %__MODULE__{}

  def new!(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)

    %__MODULE__{
      decision: Decision.new!(Map.put(attrs, :decision_type, :steering)),
      token_biases: Map.get(attrs, :token_biases, %{}),
      temperature: Map.get(attrs, :temperature),
      banned_token_ids: Map.get(attrs, :banned_token_ids, []),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  defp normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end
end
