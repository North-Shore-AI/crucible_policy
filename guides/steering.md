# Steering

`SteeringPlan.fuse/2` applies token biases and weighted energy penalties to a
candidate logits list. Energy terms can be scalar, token-indexed lists, or maps.

```elixir
plan =
  SteeringPlan.new!(
    trace_id: "trace-1",
    energies: [%{source: :policy_rule, kind: :safety, energy: %{4 => 1.2}, weight: 0.5}]
  )

SteeringPlan.fuse(plan, logits)
```

The policy layer emits steering plans. Runtime adapters turn those plans into
logits processors or custom-loop callbacks.
