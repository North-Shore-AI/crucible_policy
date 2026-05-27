alias CruciblePolicy.RouteDecision
alias CrucibleSignal.{SignalRef, TensorSummary}
alias CrucibleSignalTrace.{ForwardTrace, SignalRecord}

trace_id = "trace-route-example"

trace =
  ForwardTrace.new!(
    trace_id: trace_id,
    model_ref: "model:fixture",
    signal_records: [
      SignalRecord.new!(
        signal_ref:
          SignalRef.for_final_logits(
            trace_id: trace_id,
            signal_id: "final_logits:0",
            model_ref: "model:fixture",
            shape: {1, 3}
          ),
        summary: TensorSummary.summarize([10.0, 0.0, -1.0], entropy: true)
      )
    ]
  )

{:ok, %RouteDecision{} = decision} = CruciblePolicy.decide(trace)

IO.inspect(%{ok: true, example: "route_decision_mock", selected_target: decision.selected_target})
