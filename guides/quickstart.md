# Quickstart

`crucible_policy` consumes Crucible signal traces and emits structured route,
gate, fusion, steering, verifier, control-vector, and shared-memory decisions.

```elixir
alias CruciblePolicy.PolicyPlan

plan = PolicyPlan.new()
{:ok, decision} = PolicyPlan.evaluate(plan, forward_trace)
```

For token-boundary generation loops, carry a `DecisionContext` and feed
incremental `SignalRecord` values through `PolicyPlan.evaluate_signal/3` or
`PolicyPlan.evaluate_incremental/3`.
