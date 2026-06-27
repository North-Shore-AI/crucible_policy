defmodule CruciblePolicy.RunningScalar do
  @moduledoc """
  Online scalar statistics for incremental token-boundary policy state.
  """

  alias CruciblePolicy.SafeTerms

  @derive Jason.Encoder
  defstruct count: 0,
            mean: nil,
            variance: nil,
            min: nil,
            max: nil,
            metadata: %{}

  @type t :: %__MODULE__{}

  def new(attrs \\ []) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)

    struct(__MODULE__, attrs)
  end

  def from_values(values) when is_list(values) do
    Enum.reduce(values, new(), &add(&2, &1))
  end

  def add(%__MODULE__{} = scalar, value) when is_number(value) do
    old_count = scalar.count || 0
    old_mean = scalar.mean || 0.0

    old_m2 =
      if old_count > 0 and is_number(scalar.variance), do: scalar.variance * old_count, else: 0.0

    new_count = old_count + 1
    delta = value - old_mean
    new_mean = old_mean + delta / new_count
    new_m2 = old_m2 + delta * (value - new_mean)

    %__MODULE__{
      scalar
      | count: new_count,
        mean: new_mean,
        variance: new_m2 / new_count,
        min: min_value(scalar.min, value),
        max: max_value(scalar.max, value)
    }
  end

  def add(%__MODULE__{} = scalar, _value), do: scalar

  defp min_value(nil, value), do: value
  defp min_value(current, value), do: min(current, value)

  defp max_value(nil, value), do: value
  defp max_value(current, value), do: max(current, value)

  defp normalize_attrs(attrs), do: SafeTerms.normalize_attrs(attrs)
end
