defmodule Crucible.Policy.PolicyConfig do
  @moduledoc """
  Deterministic policy replay configuration.
  """

  @derive Jason.Encoder
  defstruct entropy_high_threshold: 2.0,
            margin_low_threshold: 0.5,
            top_k: 10,
            top_k_stability_threshold: 0.5,
            spilled_energy_threshold: nil,
            hidden_norm_drift_threshold: 5.0,
            trajectory_drift_threshold: 1.0,
            fail_on_missing_required?: true

  @type t :: %__MODULE__{
          entropy_high_threshold: number(),
          margin_low_threshold: number(),
          top_k: pos_integer(),
          top_k_stability_threshold: number(),
          spilled_energy_threshold: number() | nil,
          hidden_norm_drift_threshold: number(),
          trajectory_drift_threshold: number(),
          fail_on_missing_required?: boolean()
        }
end
