defmodule CruciblePolicy.SharedMemoryWrite do
  @moduledoc """
  Trace-backed shared memory write request.
  """

  @derive Jason.Encoder
  defstruct memory_ref: nil,
            trace_id: nil,
            signal_refs: [],
            summary: %{},
            visibility: :run,
            retention: :ephemeral,
            metadata: %{}

  @type t :: %__MODULE__{}
end
