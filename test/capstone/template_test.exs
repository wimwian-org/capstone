defmodule Capstone.TemplateTest do
  use ExUnit.Case, async: true

  alias Capstone.Template

  @names %{module: "NewWebApp", app: "new_web_app", name: "new_web_app"}

  describe "text?/1" do
    test "true for UTF-8 source, false for binary" do
      assert Template.text?("defmodule X do\nend\n")
      # The first 8 bytes of a PNG — priv/static/favicon.ico is real payload.
      refute Template.text?(<<137, 80, 78, 71, 13, 10, 26, 10>>)
    end
  end

  describe "capture/2 and render/2" do
    test "substitutes both stems and verifies by rendering back" do
      source = "defmodule NewWebApp.Repo do\n  @otp_app :new_web_app\nend\n"

      assert {:ok, template} = Template.capture(source, @names)

      assert template ==
               "defmodule <%= @module %>.Repo do\n  @otp_app :<%= @app %>\nend\n"

      assert Template.render(template, @names) == source
    end

    test "render/2 materialises into a differently named project" do
      template = "defmodule <%= @module %>.Repo do\n  @otp_app :<%= @app %>\nend\n"

      assert Template.render(template, %{
               module: "MyCacheApp",
               app: "my_cache_app",
               name: "my_cache_app"
             }) == "defmodule MyCacheApp.Repo do\n  @otp_app :my_cache_app\nend\n"
    end

    test "render/2 supplies @name even though capture never introduces it" do
      assert Template.render("<%= @name %>", @names) == "new_web_app"
    end

    test "escapes pre-existing EEx so it survives the round trip" do
      # Real shape from core_components.ex in the phx.new baseline.
      source = """
      defmodule NewWebApp.Comp do
        # <%= for action <- @action do %>
        #   <%= action %>
        # <% end %>
        @otp_app :new_web_app
      end
      """

      assert {:ok, template} = Template.capture(source, @names)
      assert Template.render(template, @names) == source
    end

    test "escaping runs before substitution, never escaping our own placeholders" do
      # The trap: escape after substituting and the template carries `<%%= @app %>`,
      # which renders as the literal text `<%= @app %>` into the generated project.
      source = ":new_web_app\n"

      assert {:ok, template} = Template.capture(source, @names)
      assert template == ":<%= @app %>\n"
      refute template =~ "<%%"
    end

    test "reports a mismatch instead of returning a template that does not round-trip" do
      # A pathological stem can be substituted INTO the escape sequence it was
      # meant to protect: "<%" escapes to "<%%", and a stem of "%" then matches
      # both percent signs. The result renders to "<%%", not "<%". Verification
      # is what turns this from a corrupt template into an error, and the offset
      # names where the two diverge.
      assert {:error, {:render_mismatch, 2}} =
               Template.capture("<% x %>", %{module: "M", app: "%", name: "n"})
    end

    test "reports a raise instead of crashing when a stem collides with an assign" do
      # Substitution runs module-first. An app stem of "module" then matches
      # inside the `<%= @module %>` just inserted, producing nested EEx that
      # cannot parse. capture/2 is public and is fed arbitrary meta-project
      # files by sub-projects B and C, so it must return rather than raise.
      assert {:error, {:render_raised, message}} =
               Template.capture("Foo\n", %{module: "Foo", app: "module", name: "n"})

      assert message =~ "syntax"
    end

    test "refuses binary input rather than raising inside EEx" do
      # EEx tokenizes a charlist; on non-UTF-8 it raises UnicodeConversionError.
      # priv/static/favicon.ico is the real payload that found this.
      png = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13>>

      assert Template.capture(png, @names) == {:error, :binary}
    end
  end

  describe "placeholder_path/2" do
    test "replaces the app stem with SDD 7.1's bare APP token" do
      # Paths are not EEx: 7.1 spells the file list {"lib/APP/cache.ex", ...}.
      assert Template.placeholder_path("lib/new_web_app/cache.ex", @names) == "lib/APP/cache.ex"
      assert Template.placeholder_path("lib/new_web_app.ex", @names) == "lib/APP.ex"
    end

    test "obeys the same segment boundary as content substitution" do
      assert Template.placeholder_path("lib/new_web_app_web/router.ex", @names) ==
               "lib/APP_web/router.ex"

      # No token boundary, so no substitution.
      assert Template.placeholder_path("lib/new_web_apparatus.ex", @names) ==
               "lib/new_web_apparatus.ex"
    end

    test "a path carrying no project name is unchanged" do
      assert Template.placeholder_path("config/config.exs", @names) == "config/config.exs"
    end

    test "resolve_path/2 is its inverse against any project" do
      other = %{module: "MyCacheApp", app: "my_cache_app", name: "my_cache_app"}

      assert Template.resolve_path("lib/APP/cache.ex", other) == "lib/my_cache_app/cache.ex"
      assert Template.resolve_path("lib/APP.ex", other) == "lib/my_cache_app.ex"

      assert Template.resolve_path("lib/APP_web/router.ex", other) ==
               "lib/my_cache_app_web/router.ex"
    end

    test "resolve_path/2 leaves a path with no token alone" do
      assert Template.resolve_path("config/config.exs", @names) == "config/config.exs"
    end

    test "placeholder_path/2 and resolve_path/2 round-trip" do
      path = "lib/new_web_app_web/live/page.ex"

      assert path |> Template.placeholder_path(@names) |> Template.resolve_path(@names) == path
    end
  end

  describe "matching precision" do
    test "does not reach into longer identifiers (the reproduced §4.1 cases)" do
      # Every one of these corrupted user code in Fireside 0.2.0.
      comp = %{module: "MyComp", app: "my_comp", name: "my_comp"}
      auth = %{module: "Auth", app: "auth", name: "auth"}
      base = %{module: "Base", app: "base", name: "base"}

      assert capture!(":my_comparison\n", comp) == ":my_comparison\n"
      assert capture!(":authorized\n", auth) == ":authorized\n"
      assert capture!("[:author, :authenticated]\n", auth) == "[:author, :authenticated]\n"
      assert capture!("base64\n", base) == "base64\n"
    end

    test "matches underscore-delimited continuations" do
      # These are name-derived and MUST be renamed: the dev and test database
      # names, and the app's own Web namespace.
      assert capture!("new_web_app_dev\n", @names) == "<%= @app %>_dev\n"
      assert capture!("new_web_app_test\n", @names) == "<%= @app %>_test\n"
      assert capture!("new_web_app_web\n", @names) == "<%= @app %>_web\n"
    end

    test "a leading underscore is a separator, not an identifier interior" do
      # Regression: this is the session cookie key in endpoint.ex. A left
      # boundary that rejected `_` left it silently unrenamed.
      assert capture!(~s|key: "_new_web_app_key"\n|, @names) ==
               ~s|key: "_<%= @app %>_key"\n|
    end

    test "matches hump-delimited continuations in PascalCase" do
      assert capture!("NewWebAppWeb.Router\n", @names) == "<%= @module %>Web.Router\n"
    end

    test "the accepted over-match is pinned, not silently tolerated" do
      # Delimited continuations match by design, so a short stem reaches further
      # than a reader might expect. This is safe ONLY because of ownership
      # scoping and the meta-project naming policy (spec §7), never because the
      # matcher is clever. Pinned so the tradeoff stays visible.
      auth = %{module: "Auth", app: "auth", name: "auth"}
      api = %{module: "Api", app: "api", name: "api"}

      assert capture!(":auth_service\n", auth) == ":<%= @app %>_service\n"
      assert capture!(":api_key\n", api) == ":<%= @app %>_key\n"

      # The PascalCase instance of the same tradeoff, and it is UNAVOIDABLE:
      # `AuthHelper` is `Auth` + an uppercase-initial continuation, structurally
      # identical to `NewWebApp` + `Web`. The 67 NewWebAppWeb occurrences in the
      # baseline REQUIRE hump continuations to match, so this one must too.
      assert capture!("AuthHelper.Thing\n", auth) == "<%= @module %>Helper.Thing\n"
    end
  end

  describe "the real phx.new baseline" do
    @baseline "priv/meta/baseline_api"
    @names %{module: "NewApiApp", app: "new_api_app", name: "new_api_app"}
    @other %{module: "MyCacheApp", app: "my_cache_app", name: "my_cache_app"}

    test "every text file round-trips byte-identically, and binaries are refused" do
      {binary, text} =
        baseline_files()
        |> Enum.split_with(&(not Template.text?(File.read!(&1))))

      # The favicon is the positive control: without it, a capture/2 that
      # silently accepted binary would pass this test unnoticed.
      assert length(binary) == 1
      for f <- binary, do: assert(Template.capture(File.read!(f), @names) == {:error, :binary})

      failures =
        for f <- text,
            source = File.read!(f),
            {:ok, template} = Template.capture(source, @names),
            Template.render(template, @names) != source,
            do: Path.relative_to(f, @baseline)

      assert failures == []
      # The count is asserted so that a baseline shrinking to nothing would
      # fail rather than pass vacuously.
      assert length(text) == 29
    end

    test "materialising to another name leaves no trace of the original" do
      leftovers =
        for f <- baseline_files(),
            source = File.read!(f),
            Template.text?(source),
            {:ok, template} = Template.capture(source, @names),
            rendered = Template.render(template, @other),
            rendered =~ ~r/new_web_app|NewWebApp/,
            do: Path.relative_to(f, @baseline)

      assert leftovers == []
    end
  end

  defp capture!(source, names) do
    {:ok, template} = Template.capture(source, names)
    template
  end

  defp baseline_files do
    @baseline
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
  end
end
