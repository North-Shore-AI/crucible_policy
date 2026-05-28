defmodule Crucible.PolicyDecision do
  @moduledoc """
  V4/V5 canonical policy decision over replayed trace evidence.
  """

  @derive Jason.Encoder
  defstruct [
    :decision_id,
    :trace_id,
    :selected_policy,
    :selected_action,
    :confidence,
    evidence: [],
    skipped_policies: [],
    fallback_path: [],
    errors: []
  ]

  @type t :: %__MODULE__{
          decision_id: String.t() | nil,
          trace_id: term(),
          selected_policy: atom() | nil,
          selected_action: atom() | nil,
          confidence: number() | nil,
          evidence: [map()],
          skipped_policies: [map()],
          fallback_path: [atom()],
          errors: [term()]
        }
end
