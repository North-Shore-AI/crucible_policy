defmodule CruciblePolicy.RouteDecision do
  @moduledoc """
  Model, role, or target route decision.
  """

  alias CruciblePolicy.{Decision, SafeTerms}

  @derive Jason.Encoder
  defstruct decision: nil,
            selected_target: nil,
            selected_model: nil,
            alternatives: [],
            metadata: %{}

  @type t :: %__MODULE__{}

  def new!(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)

    %__MODULE__{
      decision:
        Decision.new!(
          attrs
          |> Map.put(:decision_type, :route)
          |> Map.put_new(:decision_id, Map.get(attrs, :decision_id))
        ),
      selected_target: Map.fetch!(attrs, :selected_target),
      selected_model: Map.get(attrs, :selected_model),
      alternatives: Map.get(attrs, :alternatives, []),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  defp normalize_attrs(attrs), do: SafeTerms.normalize_attrs(attrs)
end
