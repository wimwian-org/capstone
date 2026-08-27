defmodule Capstone.Vendor.Vex.ErrorRenderers.EEx do
  @moduledoc false

  @behaviour Capstone.Vendor.Vex.ErrorRenderer

  @doc """

  ## Examples

      iex> Capstone.Vendor.Vex.ErrorRenderers.EEx.message(nil, "default")
      "default"
      iex> Capstone.Vendor.Vex.ErrorRenderers.EEx.message([message: "override"], "default")
      "override"
      iex> Capstone.Vendor.Vex.ErrorRenderers.EEx.message([message: "Context #<%= value %>"], "default", value: 2)
      "Context #2"
  """
  def message(options, default, context \\ []) do
    message = Capstone.Vendor.Vex.ErrorRenderer.get_message(options, default)
    message |> EEx.eval_string(context)
  end
end
