# Run as: elixir -pa <ebin> test/support/determinism_probe.exs fwd|rev [exs|manifest]
#
# The second argument names the SUBJECT, and defaults to `exs` so
# Capstone.ExsTest's two-argument invocation keeps its exact behaviour.
#
#   exs       — a flat map whose KEYS are interned in the requested order.
#               Capstone.Source owns map key order.
#   manifest  — plugins whose NAMES are interned in the requested order and
#               are then supplied to the encoder in that order. Capstone.Source
#               cannot help here: the leak would be in LIST order, which is
#               Capstone.Manifest's own, and sorting by an atom is only
#               creation-order independent because Erlang orders atoms by text.
[direction | rest] = System.argv()
subject = List.first(rest) || "exs"

keys = ~w(zq_alpha zq_beta zq_gamma zq_delta base plugins schema_version)
ordered = if direction == "rev", do: Enum.reverse(keys), else: keys

# Intern the atoms in the requested order — this is what the encoder must be
# immune to. The atoms MUST be created here, at run time, from a list that is
# a compile-time literal: written as atom literals they would all intern in
# source order in both directions, and an existing-atom lookup would raise on
# the first key. `:erlang.binary_to_atom/2` rather than its String wrapper
# because the input is this fixed seven-element list and nothing else, so the
# atom-exhaustion rule the wrapper's name trips has no surface here.
atoms = Enum.map(ordered, &:erlang.binary_to_atom(&1, :utf8))

timestamp = "2026-08-11T00:00:00Z"
digest = "sha256:" <> String.duplicate("a", 64)

# struct!/2, never a `%Mod{}` literal. A literal is expanded at COMPILE time —
# the compiler calls Mod.__struct__/1 during expansion — and an .exs script is
# compiled in full before any of it runs, so the three manifest structs below
# would have to resolve even for the `exs` subject, which never touches them.
# That silently couples the `exs` probe to Capstone.Manifest's ebin: under a
# narrower -pa the script would die at compile time on stderr, System.cmd/3
# would not raise, and both directions would return "". struct!/2 resolves at
# run time and still enforces @enforce_keys.
plugin = fn name ->
  struct!(Capstone.Manifest.Plugin,
    applied_at: timestamp,
    files: [
      struct!(Capstone.Manifest.FileEntry,
        hash: digest,
        key: nil,
        mode: :sole_owner,
        path: "lib/#{name}.ex"
      )
    ],
    name: name,
    origin: {:hex, "capstone_#{name}", "1.0.0"},
    version: "1.0.0"
  )
end

encoded =
  case subject do
    "exs" ->
      Capstone.Source.encode!(Map.new(Enum.zip(atoms, ordered)))

    "manifest" ->
      Capstone.Manifest.encode!(
        struct!(Capstone.Manifest,
          base: :web,
          plugins: Enum.map(atoms, plugin),
          config_digest: digest,
          generated_at: timestamp,
          schema_version: 1,
          capstone_version: "1.0.0"
        )
      )
  end

IO.puts(:crypto.hash(:sha256, encoded) |> Base.encode16(case: :lower))
