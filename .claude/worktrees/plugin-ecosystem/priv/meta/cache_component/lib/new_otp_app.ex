defmodule NewOtpApp do
  @moduledoc """
  Documentation for `NewOtpApp`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> NewOtpApp.hello()
      :world

  """
  defdelegate fetch(key, fun), to: NewOtpApp.Cache

  def hello do
    :world
  end
end
