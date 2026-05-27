defmodule CruciblePolicy.FusionDecision do
  @moduledoc """
  Contract for combining candidate signal or logits streams.
  """

  alias CruciblePolicy.Decision

  @derive Jason.Encoder
  defstruct decision: nil,
            fusion_mode: nil,
            weights: %{},
            input_refs: [],
            output_ref: nil,
            metadata: %{}

  @type t :: %__MODULE__{}

  def new!(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)

    %__MODULE__{
      decision: Decision.new!(Map.put(attrs, :decision_type, :fusion)),
      fusion_mode: Map.fetch!(attrs, :fusion_mode),
      weights: Map.get(attrs, :weights, %{}),
      input_refs: Map.get(attrs, :input_refs, []),
      output_ref: Map.get(attrs, :output_ref),
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
