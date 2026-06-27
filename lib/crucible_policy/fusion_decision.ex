defmodule CruciblePolicy.FusionDecision do
  @moduledoc """
  Contract for combining candidate signal or logits streams.
  """

  alias CruciblePolicy.{Decision, SafeTerms}

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

  defp normalize_attrs(attrs), do: SafeTerms.normalize_attrs(attrs)
end
