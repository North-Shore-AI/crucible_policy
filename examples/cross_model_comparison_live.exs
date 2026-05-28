alias CrucibleSignalTrace.Ingest

argv =
  case System.argv() do
    ["--" | rest] -> rest
    args -> args
  end

{opts, positional, invalid} =
  OptionParser.parse(argv, strict: [out: :string], aliases: [o: :out])

if invalid != [] or positional == [] do
  raise """
  Usage:
    mix run examples/cross_model_comparison_live.exs -- [--out report.json] TRACE_OR_GLOB [...]
  """
end

paths =
  positional
  |> Enum.flat_map(fn path ->
    case Path.wildcard(path) do
      [] -> [path]
      matches -> matches
    end
  end)
  |> Enum.uniq()
  |> Enum.sort()

traces = Enum.map(paths, &Ingest.from_jsonl!/1)
report = CruciblePolicy.compare_traces(traces)

case opts[:out] do
  nil ->
    :ok

  out ->
    File.mkdir_p!(Path.dirname(out))
    File.write!(out, Jason.encode!(report, pretty: true))
end

IO.inspect(%{
  ok: true,
  example: "cross_model_comparison_live",
  trace_count: report.trace_count,
  model_count: report.model_count,
  status: report.status,
  out: opts[:out]
})
