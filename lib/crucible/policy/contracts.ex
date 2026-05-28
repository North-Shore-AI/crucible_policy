defmodule Crucible.Policy.CorrectionPlan do
  @moduledoc "V4/V5 active correction placeholder; degraded unless capabilities advertise support."
  @derive Jason.Encoder
  defstruct kind: :none, required_capabilities: [], fallback: :skip_with_trace_note
end

defmodule Crucible.Policy.ProjectionHandoffSpec do
  @moduledoc "V4/V5 latent projection handoff placeholder."
  @derive Jason.Encoder
  defstruct [:source_signal, :target_space, :projection_kind, :required_capability]
end

defmodule Crucible.Policy.ContrastivePassPlan do
  @moduledoc "V4/V5 auxiliary contrastive pass placeholder."
  @derive Jason.Encoder
  defstruct kind: :token_aware_attention_mask,
            required_capability: :auxiliary_forward_pass,
            fallback: :skip_with_trace_note
end
