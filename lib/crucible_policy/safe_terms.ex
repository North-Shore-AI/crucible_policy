defmodule CruciblePolicy.SafeTerms do
  @moduledoc false

  @key_map %{
    "action" => :action,
    "alternatives" => :alternatives,
    "accumulated_uncertainty" => :accumulated_uncertainty,
    "banned_token_ids" => :banned_token_ids,
    "base_model" => :base_model,
    "budget" => :budget,
    "capabilities" => :capabilities,
    "confidence" => :confidence,
    "confidence_band" => :confidence_band,
    "control_ref" => :control_ref,
    "control_type" => :control_type,
    "count" => :count,
    "decision" => :decision,
    "decision_id" => :decision_id,
    "decision_type" => :decision_type,
    "decisions" => :decisions,
    "dtype" => :dtype,
    "early_exit_threshold" => :early_exit_threshold,
    "elapsed_ms" => :elapsed_ms,
    "energies" => :energies,
    "evidence_refs" => :evidence_refs,
    "fusion_mode" => :fusion_mode,
    "high_entropy_threshold" => :high_entropy_threshold,
    "input_refs" => :input_refs,
    "intra_model_kl_threshold" => :intra_model_kl_threshold,
    "kind" => :kind,
    "max" => :max,
    "max_tokens" => :max_tokens,
    "mean" => :mean,
    "memory_ref" => :memory_ref,
    "metadata" => :metadata,
    "missing_evidence" => :missing_evidence,
    "min" => :min,
    "mode" => :mode,
    "moderate_entropy_threshold" => :moderate_entropy_threshold,
    "output_ref" => :output_ref,
    "passed?" => :passed?,
    "policy_ref" => :policy_ref,
    "projection_ref" => :projection_ref,
    "reason" => :reason,
    "record_id" => :record_id,
    "required_capability" => :required_capability,
    "required_missing" => :required_missing,
    "retention" => :retention,
    "running_entropy" => :running_entropy,
    "runtime_profile" => :runtime_profile,
    "scale" => :scale,
    "score" => :score,
    "selected_model" => :selected_model,
    "selected_target" => :selected_target,
    "shape" => :shape,
    "signal_refs" => :signal_refs,
    "signal_window" => :signal_window,
    "signal_window_size" => :signal_window_size,
    "signal_type" => :signal_type,
    "source_signal_refs" => :source_signal_refs,
    "steering_entropy_threshold" => :steering_entropy_threshold,
    "storage_ref" => :storage_ref,
    "summary" => :summary,
    "supported_capabilities" => :supported_capabilities,
    "supported_kinds" => :supported_kinds,
    "surface_capabilities" => :surface_capabilities,
    "surface_id" => :surface_id,
    "tap_id" => :tap_id,
    "tap_kinds" => :tap_kinds,
    "target_tap" => :target_tap,
    "temperature" => :temperature,
    "thinker_confidence" => :thinker_confidence,
    "token_biases" => :token_biases,
    "token_index" => :token_index,
    "trace_id" => :trace_id,
    "trajectory_anomaly_threshold" => :trajectory_anomaly_threshold,
    "uncertainty" => :uncertainty,
    "vector_id" => :vector_id,
    "verifier_ref" => :verifier_ref,
    "verifier_confidence" => :verifier_confidence,
    "verifier_margin_threshold" => :verifier_margin_threshold,
    "visibility" => :visibility,
    "worker_confidence" => :worker_confidence,
    "weights" => :weights
  }

  def normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  def normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {Map.get(@key_map, key, key), normalize_nested(value)}
      {key, value} -> {key, normalize_nested(value)}
    end)
  end

  def normalize_nested(value) when is_struct(value), do: value
  def normalize_nested(value) when is_map(value), do: normalize_attrs(value)
  def normalize_nested(value) when is_list(value), do: Enum.map(value, &normalize_nested/1)
  def normalize_nested(value), do: value

  def atomize_existing(nil), do: nil
  def atomize_existing(value) when is_atom(value), do: value

  def atomize_existing(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  def atomize_existing(value), do: value
end
