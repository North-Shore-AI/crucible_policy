# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

- Added V4 offline policy replay over canonical `Crucible.ForwardTrace` values
  with `Crucible.PolicyDecision`, `PolicyConfig`, entropy, margin, and skip
  metadata rules.
- Added incremental `PolicyPlan` evaluation with `DecisionContext` and `RunningScalar`.
- Added structural uncertainty fields for MoE entropy, logit-lens stability, intra-model KL, and optional inter-model disagreement.
- Added logit-energy fusion, token-boundary steering validation, active-control handoff contracts, examples, and guides.
