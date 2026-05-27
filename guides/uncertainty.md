# Uncertainty

`Uncertainty` separates completed-trace entropy from token entropy. Completed
traces populate `trace_entropy`; incremental records populate `token_entropy`
and update `DecisionContext.running_entropy`.

Structural fields include MoE router entropy, logit-lens trajectory stability,
intra-model logit-lens/final-logit divergence, and optional inter-model
disagreement when a caller provides parallel-model evidence.
