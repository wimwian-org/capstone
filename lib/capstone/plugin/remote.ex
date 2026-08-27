defmodule Capstone.Plugin.Remote do
  @moduledoc """
  Downloads plugin archives from this repository's GitHub releases into a
  local cache directory, so `priv/plugins/` is never committed to source
  control or shipped inside the hex package — see
  `Capstone.Plugin.Registry.default_dir/0`.

  Uses `:httpc`/`:ssl` (OTP stdlib) and OTP 27's built-in `:json` module
  rather than a hex HTTP/JSON client: this module is reached from
  `mix capstone.new`/`mix capstone.update`, both of which run inside a
  consuming project, so `Capstone.BoundaryGuard`'s ban on a runtime
  dependency applies here the same as everywhere else under `lib/`.

  Archives are content-addressed (the sha in `<type>-<elixir>-<capstone>-
  <sha>.tar.gz`), so a file already present in the cache under its exact
  published name is never re-downloaded or re-verified — a name match
  already is a content match, the same assumption
  `Capstone.Plugin.Registry.resolve!/4` makes about `priv/plugins/` today.

  A `GITHUB_TOKEN`/`GH_TOKEN` environment variable is used when present
  (better rate limits, and this keeps working if the repository is ever
  made private again), but is not required: the repository is public, and
  a release asset's `browser_download_url` needs no authentication to
  fetch.
  """

  @owner "wimwian-org"
  @repo "capstone"
  @releases_url "https://api.github.com/repos/#{@owner}/#{@repo}/releases"
  @user_agent ~c"capstone-plugin-registry"

  @typedoc "One release asset: its published filename and the URL to fetch its bytes from."
  @type asset :: %{name: String.t(), url: String.t()}

  @typedoc "The injected HTTP seam every function here goes through — real by default, fake in tests."
  @type fetch :: (String.t() -> {:ok, binary()} | {:error, term()})

  defmodule Error do
    @moduledoc "Raised when listing or downloading a release asset fails."
    defexception [:message]
  end

  @doc """
  Ensures every published `type` archive exists in `dir`, downloading
  whatever is missing. Files already present are left untouched — see the
  moduledoc for why that is safe rather than stale.
  """
  @spec sync!(atom(), Path.t(), fetch()) :: :ok
  def sync!(type, dir, fetch \\ &http_get!/1) do
    File.mkdir_p!(dir)
    prefix = Atom.to_string(type) <> "-"

    fetch
    |> list_assets!()
    |> Enum.filter(&String.starts_with?(&1.name, prefix))
    |> Enum.each(&ensure_downloaded!(&1, dir, fetch))

    :ok
  end

  @doc """
  Every asset attached to any release of this repository, across every
  page. Returned oldest-page-first; caller order does not depend on it.
  """
  @spec list_assets!(fetch()) :: [asset()]
  def list_assets!(fetch \\ &http_get!/1) do
    Stream.iterate(1, &(&1 + 1))
    |> Enum.reduce_while([], fn page, acc ->
      case releases_page!(fetch, page) do
        [] -> {:halt, acc}
        releases -> {:cont, acc ++ Enum.flat_map(releases, &assets_of/1)}
      end
    end)
  end

  defp releases_page!(fetch, page) do
    url = "#{@releases_url}?per_page=100&page=#{page}"

    case fetch.(url) do
      {:ok, body} -> decode_list!(body, url)
      {:error, reason} -> raise Error, message: "GET #{url} failed: #{inspect(reason)}"
    end
  end

  defp assets_of(release) do
    for %{"name" => name, "browser_download_url" => url} <- Map.get(release, "assets", []) do
      %{name: name, url: url}
    end
  end

  defp ensure_downloaded!(asset, dir, fetch) do
    dest = Path.join(dir, asset.name)

    unless File.regular?(dest) do
      case fetch.(asset.url) do
        {:ok, body} -> File.write!(dest, body)
        {:error, reason} -> raise Error, message: "GET #{asset.url} failed: #{inspect(reason)}"
      end
    end
  end

  defp decode_list!(body, url) do
    case :json.decode(body) do
      list when is_list(list) -> list
      other -> raise Error, message: "#{url} returned #{inspect(other)}, expected a list"
    end
  rescue
    e ->
      reraise Error,
              [message: "#{url} returned unparseable JSON: #{Exception.message(e)}"],
              __STACKTRACE__
  end

  # coveralls-ignore-start
  # The real HTTP effect, reachable only via the `fetch \\ &http_get!/1`
  # default — every other test injects a fake `fetch` to stay hermetic (see
  # the moduledoc), so this only runs for real under `@tag :toolchain`
  # (test/integration/plugin_lifecycle_test.exs), which `ExUnit.start(exclude:
  # ...)` removes from the coverage run. Same structural reason
  # `Capstone.New.Bootstrap`'s moduledoc gives for its one ignored line.
  defp http_get!(url) do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    request = {String.to_charlist(url), headers()}

    case :httpc.request(:get, request, [autoredirect: true], body_format: :binary) do
      {:ok, {{_version, 200, _reason}, _headers, body}} -> {:ok, body}
      {:ok, {{_version, status, reason}, _headers, _body}} -> {:error, {status, reason}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp headers do
    base = [{~c"User-Agent", @user_agent}]

    case System.get_env("GITHUB_TOKEN") || System.get_env("GH_TOKEN") do
      nil -> base
      token -> [{~c"Authorization", ~c"Bearer #{token}"} | base]
    end
  end

  # coveralls-ignore-stop
end
