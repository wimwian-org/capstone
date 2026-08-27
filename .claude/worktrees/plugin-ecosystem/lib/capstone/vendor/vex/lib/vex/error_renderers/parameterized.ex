defmodule Capstone.Vendor.Vex.ErrorRenderers.Parameterized do
  @moduledoc false

  @behaviour Capstone.Vendor.Vex.ErrorRenderer

  @doc """

  ## Examples

      iex> Capstone.Vendor.Vex.ErrorRenderers.Parameterized.message(nil, "default")
      [message: "default", context: []]
      iex> Capstone.Vendor.Vex.ErrorRenderers.Parameterized.message([message: "override"], "default")
      [message: "override", context: []]
      iex> Capstone.Vendor.Vex.ErrorRenderers.Parameterized.message([message: "Context #<%= value %>"], "default", value: 2)
      [message: "Context #<%= value %>", context: [value: 2]]
  """
  def message(options, default, context \\ []) do
    message = Capstone.Vendor.Vex.ErrorRenderer.get_message(options, default)
    [message: message, context: context]
  end
end
