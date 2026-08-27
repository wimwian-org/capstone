# Dialyzer warnings deliberately suppressed, each with a reason.
#
# Entries are `{file}` / `{file, warning}` / `{file, warning, line}` tuples or
# regexes. `list_unused_filters: true` is set in mix.exs, so a filter that no
# longer matches fails the run rather than being reported and passed over --
# which is what will happen to the one below the moment upstream fixes its
# specs. That is the intended signal to delete it.
[
  # Vendored third-party source. Eight warnings in sourceror 1.12.2 --
  # one `opaque_match` in code/common.ex and seven `missing_range` across
  # zipper.ex, fast_zipper.ex and code/common.ex. They are upstream's specs,
  # not ours, and not something we can fix without diverging from a tree we
  # deliberately keep pristine (the only patches recorded in vendor/vendor.exs
  # are the two that stop it reading Capstone's README.md at compile time).
  #
  # Seven of the eight are invisible unless `:extra_return`/`:missing_return`
  # are in `flags:`, which is why they're both there in mix.exs.
  ~r"^lib/capstone/vendor/"
]
