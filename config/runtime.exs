import Config

# Unlike config/dev.exs (and any other compile-time `#{Mix.env()}.exs`),
# this file is evaluated AFTER the current project is compiled -- see
# `Devops.Config`'s own moduledoc note that every `devops.*` task declares
# `@requirements ["app.start"]`, which forces a compile first -- so the
# vendored `DotenvParser` (compiled as part of this very app) is always
# available here, never raising the `UndefinedFunctionError` a truly
# fresh `rm -rf _build && mix compile` hits if this same call is made from
# `config/dev.exs` instead (compile-time config runs before the current
# project itself is compiled).
#
# `.env` is loaded first as a shared base, then `.env.#{config_env()}`
# (`.env.dev`, `.env.test`, `.env.prod`) on top of it, so an env-specific
# value overrides the shared one for the same key. Both calls are no-ops
# when their file is absent -- most checkouts have neither. The trailing
# `:ok` matters: this file's last expression is itself validated as
# config data, and a bare `for` comprehension returns a list that fails
# that check.
for file <- [".env", ".env.#{config_env()}"], File.exists?(file) do
  DotenvParser.load_file(file)
end

:ok
