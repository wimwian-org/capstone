defmodule NewApiApp.Cache do
  @moduledoc """
  A tiny read-through cache for NewApiApp.
  """

  @doc "Fetches `key`, computing it with `fun` on a miss."
  def fetch(key, fun) when is_function(fun, 0) do
    case :persistent_term.get({__MODULE__, key}, :miss) do
      :miss ->
        value = fun.()
        :persistent_term.put({__MODULE__, key}, value)
        value

      value ->
        value
    end
  end
end
