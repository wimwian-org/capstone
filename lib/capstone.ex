defmodule Capstone do
  @moduledoc """
  Top-level namespace for the `capstone` mix-generator package.

  There is no application logic here — `mix capstone.new` (`Mix.Tasks.Capstone.New`),
  `mix capstone.update` (`Mix.Tasks.Capstone.Update`) and the `mix capstone.plugin.*`
  tasks are the actual entry points; see their moduledocs for what each does.
  """

  @doc """
  Placeholder left over from `mix new`. Not part of this package's public API.
  """
  @spec hello() :: :world
  def hello do
    :world
  end
end
