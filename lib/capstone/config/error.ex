defmodule Capstone.Config.Error do
  @moduledoc """
  Raised by `Capstone.Config.read!/1` and `Capstone.Config.read_string!/1`
  when `target.exs` fails validation.
  """

  defexception [:errors]

  @type t :: %__MODULE__{errors: [Capstone.Config.error()]}

  @impl true
  @spec message(t()) :: String.t()
  def message(%__MODULE__{errors: errors}) do
    "invalid target.exs:\n" <> Enum.map_join(errors, "\n", &("  - " <> inspect(&1)))
  end
end
