# target.exs -- what this project asked Capstone for.
#
# Written by `mix capstone.gen.config --base web`. Every key below is OPTIONAL
# except the four at the top: delete any of them and `base: :web` supplies
# the value its comment names as the default. They are written out so the whole
# shape is visible and editable in one place.
#
# Overrides deep-merge into the preset, so naming one key leaves the rest of its
# section alone. No resolution rule reaches a key this file shows, so nothing here is ever overridden.
#
# This file is the record of the REQUEST. `plugin.exs` is the record of what was
# actually written and with which content hashes -- that one is not edited by
# hand.
%{
  schema_version: 1,

  # :api | :web | :both. Every project has a web component; this says which
  # surface it exposes.
  base: :web,

  # Must be [] below schema_version 2.
  plugins: [],

  project: [
    name: "",                    # String.t(), default "NAME"
    module: MyApp,               # module(), default MODULE
    app: :my_app,                # atom(), default :APP
    github_org: ""               # String.t(), default "ORG"
  ],
  security: [
    envelope_encryption: false,  # boolean(), default false
    cloak: false                 # boolean(), default false
  ],
  container: [
    local_ci: true,              # boolean(), default true
    sidecars: [
      valkey: false,             # boolean(), default false
      openbao: false,            # boolean(), default false
      nginx: false               # boolean(), default false
    ]
  ]
}
