alias CruciblePolicy.{DecisionContext, PolicyPlan, SteeringPlan}
alias CrucibleSignal.{SignalRef, TensorSummary}
alias CrucibleSignalTrace.SignalRecord

trace_id = "trace-policy-plan-example"
plan = PolicyPlan.new(high_entropy_threshold: 10.0, steering_entropy_threshold: 1.0)
context = DecisionContext.new(trace_id: trace_id, runtime_profile: %{model_id: "model:fixture"})

record =
  SignalRecord.new!(
    signal_ref:
      SignalRef.for_final_logits(
        trace_id: trace_id,
        signal_id: "final_logits:step:0",
        model_ref: "model:fixture",
        token_index: 0,
        shape: {1, 3}
      ),
    summary: TensorSummary.summarize([0.0, 0.0, 0.0], entropy: true)
  )

{:steer, %SteeringPlan{} = steering, next_context} =
  PolicyPlan.evaluate_signal(plan, record, context)

IO.inspect(%{
  ok: true,
  example: "policy_plan_live",
  mode: steering.mode,
  entropy_count: next_context.running_entropy.count
})
