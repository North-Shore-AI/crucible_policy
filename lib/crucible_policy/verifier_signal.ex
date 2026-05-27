defmodule CruciblePolicy.VerifierSignal do
  @moduledoc """
  Verifier score or critique signal over trace evidence.
  """

  @derive Jason.Encoder
  defstruct verifier_ref: nil,
            trace_id: nil,
            score: nil,
            passed?: nil,
            evidence_refs: [],
            metadata: %{}

  @type t :: %__MODULE__{}
end
