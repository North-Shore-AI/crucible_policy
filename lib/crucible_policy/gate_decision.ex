defmodule CruciblePolicy.GateDecision do
  @moduledoc """
  Continue, stop, branch, verify, retry, reject, or constrain decision.
  """

  alias CruciblePolicy.{Decision, SafeTerms}

  @actions [:continue, :stop, :escalate, :branch, :verify, :retry, :reject, :constrain]

  @derive Jason.Encoder
  defstruct decision: nil, action: nil, reason: nil, metadata: %{}

  @type t :: %__MODULE__{}

  def new!(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)
    action = Map.fetch!(attrs, :action)

    unless action in @actions do
      raise ArgumentError, "invalid gate action: #{inspect(action)}"
    end

    %__MODULE__{
      decision: Decision.new!(Map.put(attrs, :decision_type, :gate)),
      action: action,
      reason: Map.get(attrs, :reason),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  def actions, do: @actions

  defp normalize_attrs(attrs), do: SafeTerms.normalize_attrs(attrs)
end
