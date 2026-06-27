defmodule CruciblePolicy.SteeringPlan do
  @moduledoc """
  Decode steering plan, initially consumed by logits processors.
  """

  alias CruciblePolicy.{Decision, SafeTerms}

  @derive Jason.Encoder
  defstruct decision: nil,
            base_model: nil,
            mode: :token_boundary,
            token_biases: %{},
            energies: [],
            temperature: nil,
            banned_token_ids: [],
            metadata: %{}

  @type t :: %__MODULE__{}

  def new!(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)

    %__MODULE__{
      decision: Decision.new!(Map.put(attrs, :decision_type, :steering)),
      base_model: Map.get(attrs, :base_model),
      mode: Map.get(attrs, :mode, :token_boundary),
      token_biases: Map.get(attrs, :token_biases, %{}),
      energies: Map.get(attrs, :energies, []),
      temperature: Map.get(attrs, :temperature),
      banned_token_ids: Map.get(attrs, :banned_token_ids, []),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  def fuse(%__MODULE__{} = plan, logits) when is_list(logits) do
    logits
    |> Enum.with_index()
    |> Enum.map(fn {logit, token_id} ->
      cond do
        token_id in plan.banned_token_ids ->
          :neg_infinity

        true ->
          logit + token_bias(plan, token_id) - energy_penalty(plan, token_id)
      end
    end)
  end

  def fuse(logits, %__MODULE__{} = plan) when is_list(logits), do: fuse(plan, logits)

  def validate_surface(%__MODULE__{mode: :in_graph}, context) do
    if supports?(context, :in_graph_steering) do
      :ok
    else
      {:error, :steering_surface_unavailable}
    end
  end

  def validate_surface(%__MODULE__{mode: mode}, _context)
      when mode in [:token_boundary, :logits_processor, :custom_loop],
      do: :ok

  def validate_surface(%__MODULE__{mode: mode}, _context),
    do: {:error, {:unsupported_steering_mode, mode}}

  defp token_bias(%__MODULE__{} = plan, token_id) do
    Map.get(plan.token_biases, token_id, Map.get(plan.token_biases, "#{token_id}", 0.0))
  end

  defp energy_penalty(%__MODULE__{} = plan, token_id) do
    plan.energies
    |> Enum.map(&weighted_energy(&1, token_id))
    |> Enum.sum()
  end

  defp weighted_energy(energy_term, token_id) when is_map(energy_term) do
    energy = Map.get(energy_term, :energy, Map.get(energy_term, "energy", 0.0))
    weight = Map.get(energy_term, :weight, Map.get(energy_term, "weight", 1.0))

    weight * energy_value(energy, token_id)
  end

  defp weighted_energy(energy, token_id), do: energy_value(energy, token_id)

  defp energy_value(value, _token_id) when is_number(value), do: value

  defp energy_value(values, token_id) when is_list(values) do
    Enum.at(values, token_id, 0.0) || 0.0
  end

  defp energy_value(values, token_id) when is_map(values) do
    Map.get(values, token_id, Map.get(values, "#{token_id}", 0.0))
  end

  defp energy_value(_value, _token_id), do: 0.0

  defp supports?(%CruciblePolicy.DecisionContext{} = context, capability) do
    CruciblePolicy.DecisionContext.supports?(context, capability)
  end

  defp supports?(%{capabilities: capabilities}, capability) when is_list(capabilities) do
    capability in Enum.map(capabilities, &normalize_capability/1)
  end

  defp supports?(_context, _capability), do: false

  defp normalize_capability(value) when is_binary(value), do: SafeTerms.atomize_existing(value)
  defp normalize_capability(value), do: value

  defp normalize_attrs(attrs), do: SafeTerms.normalize_attrs(attrs)
end
