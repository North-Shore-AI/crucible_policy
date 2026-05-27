# Active Control

`ControlVector.handoff/2` and `SharedMemoryWrite.handoff/2` fail closed unless
the caller supplies the required capability.

```elixir
{:ok, handoff} = ControlVector.handoff(vector, [:inject])
{:error, gate_decision} = ControlVector.handoff(vector, [])
```

This keeps active tensor mutation outside policy evaluation and prevents
unsupported surfaces from pretending they applied a control vector.
