<p align="center">
  <img src="assets/crucible_policy.svg" width="200" height="200" alt="crucible_policy logo" />
</p>

<p align="center">
  <a href="https://github.com/North-Shore-AI/crucible_policy">
    <img alt="GitHub: crucible_policy" src="https://img.shields.io/badge/GitHub-crucible_policy-0b0f14?logo=github" />
  </a>
  <a href="https://github.com/North-Shore-AI/crucible_policy/blob/main/LICENSE">
    <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-0b0f14.svg" />
  </a>
</p>

# CruciblePolicy

Routing, gating, fusion, uncertainty, verifier, shared memory, and steering
decision contracts over Crucible signal traces.

## Stack Position

`crucible_policy` sits above signal traces. It consumes bounded evidence and
emits structured decisions without owning model execution or Trinity product
flows.

## Installation

```elixir
def deps do
  [
    {:crucible_policy, "~> 0.1.0"}
  ]
end
```

## Boundary

This package owns policy and decision contracts. Bumblebee logits processors
and Trinity orchestration consume these decisions but are not owned here.

## Usage

```elixir
alias CruciblePolicy.{DecisionContext, LogitSteering, PolicyPlan, SteeringPlan}

{:ok, route_decision} = CruciblePolicy.decide(forward_trace)

steering =
  SteeringPlan.new!(
    trace_id: forward_trace.trace_id,
    token_biases: %{42 => 1.25},
    banned_token_ids: [0]
  )

steered_logits = LogitSteering.apply([0.1, 0.2, 0.3], steering)

plan = PolicyPlan.new()
context = DecisionContext.new(trace_id: "trace-1", runtime_profile: %{model_id: "model:fixture"})
{:continue, context} = PolicyPlan.evaluate_incremental(plan, %{signals: []}, context)
```

## Model Boundary

This library is model-agnostic. Model names and modified Trinity model profiles
belong in callers, examples, or downstream adapters. Policy decisions operate on
Crucible signal and trace contracts and do not require a specific model family.

## Guides

- [Quickstart](guides/quickstart.md)
- [Concepts](guides/concepts.md)
- [Incremental Policy](guides/incremental_policy.md)
- [Offline Policy Replay](guides/offline_policy_replay.md)
- [Uncertainty](guides/uncertainty.md)
- [Steering](guides/steering.md)
- [Active Control](guides/active_control.md)
- [Working Examples](guides/working_examples.md)
- [Testing](guides/testing.md)

Documentation can be generated with `mix docs` and published to HexDocs.

## Status

Status: `policy-ladder-cross-model-passing`.

Policy replay evaluates canonical `Crucible.ForwardTrace` values with entropy,
margin, top-k stability, spilled-energy, hidden-state norm drift, trajectory
drift, and dry-run correction-plan policies. Missing optional signals produce
explicit skip metadata rather than hidden fallbacks.

`CruciblePolicy.compare_traces/2` and
`Crucible.Policy.CrossModelComparison.compare/2` build bounded cross-model
reports over real traces without copying raw tensor arrays. The current
real-trace gate exercised the Python/PyTorch `gpt2` and
`hf-internal-testing/tiny-random-gpt2` traces and wrote:

```text
tmp/crucible_v5/reports/crucible_policy_cross_model_python_phase16.json
tmp/crucible_v5/transcripts/crucible_policy_cross_model_python_phase16.log
```
