# Used by "mix format"
#
# `priv/` is deliberately absent: it holds EEx payload templates and baseline
# fixtures, neither of which is ours to format.
#
# `lib/capstone/vendor/` is excluded by COMPUTING the lib inputs, because
# there is no exclude form: it is other people's source, and reformatting it
# would change the tree digest `elixir scripts/vendor.exs check` guards.
lib_inputs =
  "lib/**/*.{ex,exs}"
  |> Path.wildcard()
  |> Enum.reject(&String.starts_with?(&1, "lib/capstone/vendor/"))

[
  inputs: ["{mix,.formatter}.exs", "config/**/*.{ex,exs}", "test/**/*.{ex,exs}"] ++ lib_inputs
]
