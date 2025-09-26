defmodule Siri.Substitutions.Behavior do
  @doc "Applies the substitution to the given text and returns the modified text."
  @callback apply_subsitition(String.t()) :: String.t()
end
