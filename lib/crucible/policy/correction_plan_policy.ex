defmodule Crucible.Policy.CorrectionPlanPolicy do
  @moduledoc "V5 dry-run correction-plan policy."

  def evaluate(trace, _config) do
    if active_correction_supported?(trace) do
      {:ok,
       %{
         policy: :correction_plan_v0,
         status: :passed,
         action: :dry_run_correction_plan,
         evidence: %{
           rule: :active_mutation_guard,
           execute_mutation?: false,
           required_capability: :active_correction
         }
       }}
    else
      {:skip,
       %{
         policy: :correction_plan_v0,
         reason: :capability_unavailable,
         required_signal: :active_correction
       }}
    end
  end

  defp active_correction_supported?(%{capability_report: %{resource_budget: budget}})
       when is_map(budget) do
    Map.get(budget, :supports_active_injection?) || Map.get(budget, "supports_active_injection?") ||
      false
  end

  defp active_correction_supported?(_trace), do: false
end
