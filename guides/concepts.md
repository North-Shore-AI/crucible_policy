# Concepts

Policies are pure contract evaluators. They do not run models, mutate tensors,
or assume a model family. Downstream runtime libraries decide whether a route,
steering plan, active injection, or shared-memory write can be executed on a
specific surface.

Completed traces use `PolicyPlan.evaluate/2`. Streaming generation uses
`DecisionContext` plus incremental signal records.
