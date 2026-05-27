defmodule CruciblePolicy.ControlVector do
  @moduledoc """
  Contract for downstream vector steering.
  """

  @derive Jason.Encoder
  defstruct vector_id: nil,
            trace_id: nil,
            source_signal_refs: [],
            storage_ref: nil,
            shape: nil,
            dtype: nil,
            metadata: %{}

  @type t :: %__MODULE__{}
end
