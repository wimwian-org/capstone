defmodule Capstone.Vendor.Sourceror.TraversalState do
  @moduledoc """
  The state struct for Capstone.Vendor.Sourceror traversal functions.
  """
  import Capstone.Vendor.Sourceror.Utils.TypedStruct

  typedstruct do
    field :acc, term()
  end
end
