defmodule Crucible.Policy.PolicyConfig do
  @moduledoc """
  Deterministic V4 policy replay configuration.
  """

  @derive Jason.Encoder
  defstruct entropy_high_threshold: 2.0,
            margin_low_threshold: 0.5,
            top_k: 10,
            spilled_energy_threshold: nil,
            fail_on_missing_required?: true

  @type t :: %__MODULE__{
          entropy_high_threshold: number(),
          margin_low_threshold: number(),
          top_k: pos_integer(),
          spilled_energy_threshold: number() | nil,
          fail_on_missing_required?: boolean()
        }
end
