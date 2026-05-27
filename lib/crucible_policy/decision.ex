defmodule CruciblePolicy.Decision do
  @moduledoc """
  Shared decision fields embedded by concrete policy decisions.
  """

  @derive Jason.Encoder
  defstruct decision_id: nil,
            trace_id: nil,
            policy_ref: nil,
            decision_type: nil,
            confidence: nil,
            uncertainty: nil,
            evidence_refs: [],
            metadata: %{}

  @type t :: %__MODULE__{}

  def new!(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)

    %__MODULE__{
      decision_id: Map.get(attrs, :decision_id, "decision:#{System.unique_integer([:positive])}"),
      trace_id: Map.fetch!(attrs, :trace_id),
      policy_ref: Map.get(attrs, :policy_ref, "crucible_policy:first_slice"),
      decision_type: Map.fetch!(attrs, :decision_type),
      confidence: Map.get(attrs, :confidence),
      uncertainty: Map.get(attrs, :uncertainty),
      evidence_refs: Map.get(attrs, :evidence_refs, []),
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
