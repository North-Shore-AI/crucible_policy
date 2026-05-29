defmodule CruciblePolicy.EvidenceRef do
  @moduledoc """
  Structured citation to trace evidence consumed by a policy decision.
  """

  alias Crucible.SignalRecord

  @derive Jason.Encoder
  defstruct kind: nil,
            trace_id: nil,
            record_id: nil,
            tap_id: nil,
            signal_type: nil,
            path: [],
            summary: %{},
            metadata: %{}

  @type t :: %__MODULE__{}

  @spec from_signal(SignalRecord.t()) :: t()
  def from_signal(%SignalRecord{} = record) do
    %__MODULE__{
      kind: :signal_record,
      trace_id: record.trace_id,
      record_id: record.signal_id,
      tap_id: record.tap_id,
      signal_type: record.signal_type,
      summary: %{
        capture_method: record.capture_method,
        capability_status: record.capability_status
      },
      metadata: record.metadata || %{}
    }
  end

  @spec id(t() | String.t()) :: String.t() | nil
  def id(%__MODULE__{record_id: id}), do: id
  def id(id) when is_binary(id), do: id
  def id(_), do: nil
end
