# Offline Policy Replay

Purpose: evaluate V4 policy rules without running a live model.

## What this covers

`Crucible.Policy.PolicyPlan.evaluate/2` consumes a canonical
`Crucible.ForwardTrace` assembled from JSONL and applies deterministic
final-logits policies with explicit skip metadata for unavailable optional
signals.

## Quickstart

```elixir
{:ok, trace} =
  CrucibleSignalTrace.Ingest.from_jsonl("../crucible_bumblebee/tmp/crucible_v4/model_forward_live.trace.jsonl")

decision = Crucible.Policy.PolicyPlan.evaluate(trace)
```

Expected decision fields:

```elixir
%Crucible.PolicyDecision{
  selected_policy: :final_logits_entropy_v0,
  selected_action: :worker,
  skipped_policies: [%{policy: :trajectory_drift_v1, reason: :hidden_state_unavailable}]
}
```

## Related guides

- [Incremental Policy](incremental_policy.md)
- [Uncertainty](uncertainty.md)
