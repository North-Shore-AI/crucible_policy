defmodule CruciblePolicy.VerifierDecision do
  @moduledoc """
  First-class verifier decision over canonical trace evidence.
  """

  alias Crucible.ForwardTrace
  alias CruciblePolicy.{Decision, Evidence, EvidenceRef, SafeTerms}

  @derive Jason.Encoder
  defstruct decision: nil,
            verifier_ref: nil,
            trace_id: nil,
            passed?: false,
            score: nil,
            evidence_refs: [],
            confidence_band: :unknown,
            metadata: %{}

  @type confidence_band :: :high | :medium | :low | :unknown
  @type t :: %__MODULE__{}

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = SafeTerms.normalize_attrs(attrs)
    evidence_refs = normalize_evidence_refs(Map.get(attrs, :evidence_refs, []))
    score = Map.get(attrs, :score)
    confidence_band = Map.get(attrs, :confidence_band) || confidence_band(score)
    passed? = Map.get(attrs, :passed?, default_passed?(score, confidence_band))

    decision =
      attrs
      |> Map.put(:decision_type, :verifier)
      |> Map.put(:confidence, score)
      |> Map.put(:evidence_refs, evidence_refs)
      |> Decision.new!()

    {:ok,
     %__MODULE__{
       decision: decision,
       verifier_ref: Map.fetch!(attrs, :verifier_ref),
       trace_id: Map.fetch!(attrs, :trace_id),
       passed?: passed?,
       score: score,
       evidence_refs: evidence_refs,
       confidence_band: confidence_band,
       metadata: Map.get(attrs, :metadata, %{})
     }}
  rescue
    error -> {:error, error}
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, decision} -> decision
      {:error, reason} -> raise ArgumentError, "invalid verifier decision: #{inspect(reason)}"
    end
  end

  @spec from_trace(ForwardTrace.t(), keyword()) :: t()
  def from_trace(%ForwardTrace{} = trace, opts \\ []) do
    evidence_refs = Evidence.refs_from_trace(trace)
    missing_evidence = Evidence.missing_entries(trace)
    degraded_evidence = Evidence.degraded_entries(trace)

    requested_score =
      Keyword.get(opts, :score, score_from_evidence(evidence_refs, missing_evidence))

    score = if missing_evidence == [], do: requested_score, else: min(requested_score, 0.34)

    new!(
      trace_id: trace.trace_id,
      verifier_ref: Keyword.get(opts, :verifier_ref, "verifier:default"),
      score: score,
      passed?: missing_evidence == [] and score >= Keyword.get(opts, :threshold, 0.5),
      evidence_refs: evidence_refs,
      confidence_band: confidence_band(score),
      metadata: %{
        missing_evidence: missing_evidence,
        degraded_evidence: degraded_evidence,
        evidence_count: length(evidence_refs)
      }
    )
  end

  @spec confidence_band(number() | nil) :: confidence_band()
  def confidence_band(nil), do: :unknown
  def confidence_band(score) when is_number(score) and score >= 0.8, do: :high
  def confidence_band(score) when is_number(score) and score >= 0.5, do: :medium
  def confidence_band(score) when is_number(score), do: :low
  def confidence_band(_score), do: :unknown

  defp default_passed?(score, _band) when is_number(score), do: score >= 0.5
  defp default_passed?(_score, _band), do: false

  defp score_from_evidence([], _missing), do: 0.0
  defp score_from_evidence(_evidence_refs, []), do: 0.86
  defp score_from_evidence(_evidence_refs, _missing), do: 0.34

  defp normalize_evidence_refs(refs) when is_list(refs) do
    Enum.map(refs, &normalize_evidence_ref/1)
  end

  defp normalize_evidence_refs(ref), do: [normalize_evidence_ref(ref)]

  defp normalize_evidence_ref(%EvidenceRef{} = ref), do: ref

  defp normalize_evidence_ref(ref) when is_map(ref) do
    attrs = SafeTerms.normalize_attrs(ref)

    struct(EvidenceRef, %{
      kind: SafeTerms.atomize_existing(Map.get(attrs, :kind)),
      trace_id: Map.get(attrs, :trace_id),
      record_id: Map.get(attrs, :record_id),
      tap_id: Map.get(attrs, :tap_id),
      signal_type: SafeTerms.atomize_existing(Map.get(attrs, :signal_type)),
      path: Map.get(attrs, :path, []),
      summary: Map.get(attrs, :summary, %{}),
      metadata: Map.get(attrs, :metadata, %{})
    })
  end
end
