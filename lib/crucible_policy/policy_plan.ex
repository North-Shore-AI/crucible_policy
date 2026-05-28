defmodule CruciblePolicy.PolicyPlan do
  @moduledoc """
  Deterministic policy thresholds for completed and incremental trace evidence.
  """

  alias Crucible.{ForwardTrace, SignalRecord}
  alias CruciblePolicy.{DecisionContext, RouteDecision, SteeringPlan, Uncertainty}

  @derive Jason.Encoder
  defstruct policy_ref: "crucible_policy:deterministic_route",
            high_entropy_threshold: 2.5,
            moderate_entropy_threshold: 1.25,
            verifier_margin_threshold: 0.15,
            trajectory_anomaly_threshold: 0.4,
            intra_model_kl_threshold: 1.0,
            steering_entropy_threshold: 1.25,
            signal_window_size: 16,
            early_exit_threshold: 0.92,
            worker_confidence: 0.82,
            thinker_confidence: 0.64,
            verifier_confidence: 0.58,
            metadata: %{}

  @type t :: %__MODULE__{}

  def new(attrs \\ []) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)
    struct(__MODULE__, attrs)
  end

  def evaluate(plan, trace, opts \\ [])

  def evaluate(%__MODULE__{} = plan, %ForwardTrace{} = trace, opts) do
    CruciblePolicy.Policy.decide(trace, Keyword.put(opts, :plan, plan))
  end

  def evaluate_signal(
        %__MODULE__{} = plan,
        %SignalRecord{} = record,
        %DecisionContext{} = context
      ) do
    context =
      context
      |> DecisionContext.put_signal(record, max_window: plan.signal_window_size)
      |> accumulate(record)

    uncertainty = context.accumulated_uncertainty

    cond do
      verifier_required?(uncertainty, plan) ->
        decision = route_decision(plan, context, :verifier, plan.verifier_confidence, uncertainty)
        {:halt, decision, DecisionContext.record_decision(context, decision)}

      thinker_required?(uncertainty, plan) ->
        decision = route_decision(plan, context, :thinker, plan.thinker_confidence, uncertainty)
        {:halt, decision, DecisionContext.record_decision(context, decision)}

      steer_required?(uncertainty, plan) ->
        steering_plan = steering_plan(plan, context, uncertainty)

        with :ok <- SteeringPlan.validate_surface(steering_plan, context) do
          {:steer, steering_plan, DecisionContext.record_decision(context, steering_plan)}
        end

      true ->
        {:continue, context}
    end
  end

  def evaluate_incremental(%__MODULE__{} = plan, fragment, %DecisionContext{} = context) do
    fragment
    |> fragment_records()
    |> Enum.reduce_while({:continue, context}, fn record, {_status, current_context} ->
      case evaluate_signal(plan, record, current_context) do
        {:continue, next_context} -> {:cont, {:continue, next_context}}
        {:steer, steering_plan, next_context} -> {:halt, {:steer, steering_plan, next_context}}
        {:halt, decision, next_context} -> {:halt, {:halt, decision, next_context}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def negotiate_early_exit(%__MODULE__{} = plan, descriptor, %DecisionContext{} = context) do
    descriptor =
      descriptor
      |> normalize_attrs()
      |> Map.put_new(:kind, :gate)
      |> Map.put_new(:action, :early_exit)
      |> Map.put_new(:signal, :logit_lens_intermediate)
      |> Map.put_new(:threshold, plan.early_exit_threshold)

    cond do
      DecisionContext.supports?(context, :early_exit) ->
        {:ok, descriptor}

      DecisionContext.supports?(context, :custom_generation_loop) ->
        {:ok, descriptor}

      Map.get(descriptor, :required, true) ->
        {:error,
         %{
           reason: :backend_not_supported,
           unsupported_required: [descriptor],
           required_capability: :early_exit
         }}

      true ->
        {:ok, %{dropped_optional: [Map.put(descriptor, :reason, :backend_not_supported)]}}
    end
  end

  defp accumulate(%DecisionContext{} = context, %SignalRecord{} = record) do
    incremental = Uncertainty.from_signal(record, context.accumulated_uncertainty)
    entropy = incremental.token_entropy

    context
    |> DecisionContext.update_uncertainty(incremental)
    |> DecisionContext.update_running_entropy(entropy)
  end

  defp verifier_required?(%Uncertainty{} = uncertainty, %__MODULE__{} = plan) do
    truthy?(uncertainty.nan_or_inf) or truthy?(uncertainty.norm_anomaly) or
      truthy?(uncertainty.cache_discontinuity) or
      contradictory_margin?(uncertainty, plan) or
      above?(uncertainty.layer_drift, plan.trajectory_anomaly_threshold) or
      below_or_equal?(
        uncertainty.logit_lens_trajectory_stability,
        1.0 - plan.trajectory_anomaly_threshold
      ) or
      above?(uncertainty.intra_model_logit_lens_kl, plan.intra_model_kl_threshold)
  end

  defp thinker_required?(%Uncertainty{} = uncertainty, %__MODULE__{} = plan) do
    above?(uncertainty.entropy, plan.high_entropy_threshold)
  end

  defp steer_required?(%Uncertainty{} = uncertainty, %__MODULE__{} = plan) do
    above?(uncertainty.entropy, plan.steering_entropy_threshold)
  end

  defp contradictory_margin?(%Uncertainty{} = uncertainty, %__MODULE__{} = plan) do
    below_margin?(uncertainty.margin, plan.verifier_margin_threshold) and
      not above?(uncertainty.entropy, plan.high_entropy_threshold)
  end

  defp route_decision(
         %__MODULE__{} = plan,
         %DecisionContext{} = context,
         target,
         confidence,
         uncertainty
       ) do
    RouteDecision.new!(
      trace_id: context.trace_id || trace_id_from_window(context.signal_window),
      policy_ref: plan.policy_ref,
      selected_target: target,
      selected_model: model_id(context),
      confidence: confidence,
      uncertainty: %{uncertainty | policy_confidence: confidence},
      evidence_refs: evidence_refs(context.signal_window),
      metadata: %{policy: :incremental, token_index: context.token_index}
    )
  end

  defp steering_plan(
         %__MODULE__{} = plan,
         %DecisionContext{} = context,
         %Uncertainty{} = uncertainty
       ) do
    SteeringPlan.new!(
      trace_id: context.trace_id || trace_id_from_window(context.signal_window),
      policy_ref: plan.policy_ref,
      confidence: plan.thinker_confidence,
      uncertainty: uncertainty,
      base_model: model_id(context),
      mode: :token_boundary,
      energies: [
        %{
          source: :policy_rule,
          kind: :uncertainty,
          energy: uncertainty.entropy || 0.0,
          weight: 0.1
        }
      ],
      metadata: %{policy: :incremental, token_index: context.token_index}
    )
  end

  defp fragment_records(%SignalRecord{} = record), do: [record]
  defp fragment_records(records) when is_list(records), do: records
  defp fragment_records(%{signals: records}) when is_list(records), do: records
  defp fragment_records(%{"signals" => records}) when is_list(records), do: records

  defp fragment_records(%{events: events}) when is_list(events),
    do: Enum.flat_map(events, &fragment_records/1)

  defp fragment_records(%{record: %SignalRecord{} = record}), do: [record]
  defp fragment_records(%{"record" => %SignalRecord{} = record}), do: [record]
  defp fragment_records(_fragment), do: []

  defp evidence_refs(records) do
    records
    |> Enum.map(& &1.signal_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.reverse()
  end

  defp trace_id_from_window([%SignalRecord{} = record | _rest]), do: record.trace_id
  defp trace_id_from_window(_records), do: "trace:unknown"

  defp model_id(%DecisionContext{runtime_profile: %{model_id: model_id}}), do: model_id
  defp model_id(%DecisionContext{runtime_profile: %{"model_id" => model_id}}), do: model_id
  defp model_id(_context), do: nil

  defp above?(value, threshold), do: is_number(value) and value >= threshold
  defp below_margin?(value, threshold), do: is_number(value) and value <= threshold
  defp below_or_equal?(value, threshold), do: is_number(value) and value <= threshold
  defp truthy?(value), do: value in [true, "true", 1]

  defp normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end
end
