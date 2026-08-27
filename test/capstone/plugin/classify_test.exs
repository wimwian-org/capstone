defmodule Capstone.Plugin.ClassifyTest do
  use ExUnit.Case, async: true

  alias Capstone.Plugin.Classify

  describe "bucket/2" do
    test "a top-level block that parses is appendable" do
      lines = ["config :app, App.Cache,", "  adapter: Nebulex.Adapters.Redis"]

      assert Classify.bucket(lines, "config/config.exs") == :contributes
    end

    test "an insertion inside a literal is not" do
      assert Classify.bucket(["      App.Cache,"], "lib/app/application.ex") == :manual
    end

    test "parsing alone is not enough — indented code must live inside a module" do
      # Both parse standalone. Appending either to the end of a file produces
      # code that does not compile, which is why column 0 is required too.
      assert Classify.bucket(["  import Nebulex.Caching"], "lib/app/cache.ex") == :manual
      assert Classify.bucket(["    alias App.Cache"], "lib/app/cache.ex") == :manual
    end

    test "unparseable top-level text is not appendable" do
      assert Classify.bucket(["defmodule Broken do"], "lib/app/x.ex") == :manual
    end

    test "non-Elixir files cannot be parsed and default to :contributes" do
      # 7.1 lists compose.yaml and assets/js/app.js as :contributes entries.
      assert Classify.bucket(["  redis:", "    image: redis:7"], "compose.yaml") == :contributes
      assert Classify.bucket(["export const Hooks = {}"], "assets/js/app.js") == :contributes
    end

    test "blank lines around a hunk do not decide the verdict" do
      assert Classify.bucket(["", "config :app, key: :v", ""], "config/config.exs") ==
               :contributes
    end

    test "an empty hunk is not appendable" do
      assert Classify.bucket([""], "config/config.exs") == :manual
    end
  end

  describe "key/3" do
    test "is the plugin name joined to the file stem" do
      assert Classify.key(:valkey, "config/runtime.exs", []) == :valkey_runtime
      assert Classify.key(:valkey, "lib/app/application.ex", []) == :valkey_application
    end

    test "a collision within a plugin gets a numeric suffix" do
      assert Classify.key(:valkey, "config/runtime.exs", [:valkey_runtime]) == :valkey_runtime_2
    end

    test "successive collisions keep counting" do
      taken = [:valkey_runtime, :valkey_runtime_2]

      assert Classify.key(:valkey, "config/runtime.exs", taken) == :valkey_runtime_3
    end
  end
end
