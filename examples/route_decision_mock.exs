alias CruciblePolicy.RouteDecision
alias Crucible.{ForwardTrace, SignalRecord, TensorSummary}

trace_id = "trace-route-example"

trace =
  ForwardTrace.new!(
    trace_id: trace_id,
    model_id: "model:fixture",
    signals: [
      SignalRecord.new!(
        trace_id: trace_id,
        signal_id: "final_logits:0",
        signal_type: :final_logits,
        model_id: "model:fixture",
        shape: [1, 3],
        tensor_summary: TensorSummary.compute([10.0, 0.0, -1.0], entropy: true)
      )
    ]
  )

{:ok, %RouteDecision{} = decision} = CruciblePolicy.decide(trace)

IO.inspect(%{ok: true, example: "route_decision_mock", selected_target: decision.selected_target})
