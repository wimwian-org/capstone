%Doctor.Config{
  exception_moduledoc_required: true,
  # ~r"^test/" is the one that matters: under MIX_ENV=test the test-env
  # elixirc_paths puts test/support/factory.ex into the app's modules, and
  # doctor fails on it for having no docs.
  #
  # lib/capstone/vendor/ is other people's source, guarded by its recorded
  # digests (scripts/vendor.exs check) rather than by our documentation
  # standard; documenting it would change the digest that check compares
  # against.
  ignore_paths: [~r"^test/", ~r"^lib/capstone/vendor/"],
  ignore_modules: [],
  min_module_doc_coverage: 90,
  min_overall_doc_coverage: 100,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false
}
