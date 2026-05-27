# Incremental Policy

`DecisionContext` stores the current trace id, runtime profile, token index,
recent signal window, accumulated uncertainty, running entropy statistics, and
prior decisions.

`PolicyPlan.evaluate_signal/3` returns one of:

- `{:continue, context}`
- `{:steer, steering_plan, context}`
- `{:halt, route_decision, context}`
- `{:error, reason}`

In v3, steering is a token-boundary contract. In-graph steering must be
explicitly advertised by the model surface before it is accepted.
