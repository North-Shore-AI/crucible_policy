defmodule CruciblePolicy.Evidence do
  @moduledoc """
  Builds evidence refs and missing/degraded entries from canonical forward traces.
  """

  alias Crucible.{CapabilityReport, ForwardTrace, SignalRecord}
  alias CruciblePolicy.{EvidenceRef, SafeTerms}

  @type missing_entry :: %{
          signal_type: atom() | String.t() | nil,
          tap_id: String.t() | nil,
          required?: boolean(),
          reason: atom() | String.t() | nil,
          impact: atom(),
          metadata: map()
        }

  @type degraded_entry :: %{
          signal_type: atom() | String.t() | nil,
          tap_id: String.t() | nil,
          requested_capture: term(),
          actual_capture: term(),
          reason: atom() | String.t() | nil,
          impact: atom(),
          metadata: map()
        }

  @spec refs_from_trace(ForwardTrace.t()) :: [EvidenceRef.t()]
  def refs_from_trace(%ForwardTrace{} = trace) do
    trace.signals
    |> Enum.map(&EvidenceRef.from_signal/1)
    |> Enum.reject(&(is_nil(&1.record_id) and is_nil(&1.signal_type)))
  end

  @spec refs_from_signals([SignalRecord.t()]) :: [EvidenceRef.t()]
  def refs_from_signals(signals) when is_list(signals) do
    Enum.map(signals, &EvidenceRef.from_signal/1)
  end

  @spec missing_entries(ForwardTrace.t()) :: [missing_entry()]
  def missing_entries(%ForwardTrace{} = trace) do
    case trace.capability_report do
      %CapabilityReport{} = report ->
        Enum.map(report.required_missing, &missing_from_capability(&1, trace, :required_missing))

      %{} = report ->
        Enum.flat_map(Map.get(report, "required_missing", []), fn entry ->
          [missing_from_map(entry, trace, :required_missing)]
        end)

      _ ->
        []
    end
  end

  @spec degraded_entries(ForwardTrace.t()) :: [degraded_entry()]
  def degraded_entries(%ForwardTrace{} = trace) do
    capability_degraded =
      case trace.capability_report do
        %CapabilityReport{} = report ->
          Enum.map(report.degraded, &degraded_from_capability(&1, trace)) ++
            Enum.map(
              report.optional_dropped,
              &degraded_from_capability(&1, trace, :optional_dropped)
            )

        %{} = report ->
          Enum.map(Map.get(report, :degraded, []), &degraded_from_map(&1, trace)) ++
            Enum.map(Map.get(report, "degraded", []), &degraded_from_map(&1, trace))

        _ ->
          []
      end

    signal_degraded =
      trace.signals
      |> Enum.filter(&(Map.get(&1, :capability_status) in [:degraded, "degraded"]))
      |> Enum.map(&degraded_from_signal/1)

    capability_degraded ++ signal_degraded
  end

  defp missing_from_capability(capability, trace, reason) do
    %{
      signal_type: capability_atom(capability),
      tap_id: nil,
      required?: true,
      reason: reason,
      impact: :blocks_confidence,
      metadata: %{trace_id: trace.trace_id, capability: capability}
    }
  end

  defp missing_from_map(entry, trace, reason) when is_map(entry) do
    %{
      signal_type: Map.get(entry, :signal_type) || Map.get(entry, "signal_type"),
      tap_id: Map.get(entry, :tap_id) || Map.get(entry, "tap_id"),
      required?: Map.get(entry, :required?, true),
      reason: Map.get(entry, :reason, reason),
      impact: Map.get(entry, :impact, :blocks_confidence),
      metadata: %{trace_id: trace.trace_id, entry: entry}
    }
  end

  defp degraded_from_capability(capability, trace, reason \\ :degraded) do
    %{
      signal_type: capability_atom(capability),
      tap_id: nil,
      requested_capture: nil,
      actual_capture: :summary_only,
      reason: reason,
      impact: :reduces_confidence,
      metadata: %{trace_id: trace.trace_id, capability: capability}
    }
  end

  defp degraded_from_map(entry, trace) when is_map(entry) do
    %{
      signal_type: Map.get(entry, :signal_type) || Map.get(entry, "signal_type"),
      tap_id: Map.get(entry, :tap_id) || Map.get(entry, "tap_id"),
      requested_capture: Map.get(entry, :requested_capture),
      actual_capture: Map.get(entry, :actual_capture, :summary_only),
      reason: Map.get(entry, :reason, :degraded),
      impact: Map.get(entry, :impact, :reduces_confidence),
      metadata: %{trace_id: trace.trace_id, entry: entry}
    }
  end

  defp degraded_from_signal(%SignalRecord{} = record) do
    %{
      signal_type: record.signal_type,
      tap_id: record.tap_id,
      requested_capture: Map.get(record.metadata, :requested_capture),
      actual_capture: record.capture_method,
      reason: record.capability_reason || :degraded,
      impact: :reduces_confidence,
      metadata: %{trace_id: record.trace_id, signal_id: record.signal_id}
    }
  end

  defp capability_atom(capability) when is_atom(capability), do: capability

  defp capability_atom(capability) when is_binary(capability),
    do: SafeTerms.atomize_existing(capability)

  defp capability_atom(_), do: nil
end
