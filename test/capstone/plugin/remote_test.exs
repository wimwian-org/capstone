defmodule Capstone.Plugin.RemoteTest do
  use ExUnit.Case, async: true

  alias Capstone.Plugin.Remote

  # A single release page, shaped like GitHub's real response (trimmed to
  # only the keys this module reads).
  defp release_json(assets) do
    encoded =
      Enum.map_join(assets, ",", fn {name, url} ->
        ~s({"name": #{inspect(name)}, "browser_download_url": #{inspect(url)}})
      end)

    ~s([{"tag_name": "v0.1.0", "assets": [#{encoded}]}])
  end

  defp fake_fetch(pages) do
    fn url ->
      case Enum.find(pages, fn {pattern, _body} -> url =~ pattern end) do
        {_pattern, {:error, _} = error} -> error
        {_pattern, body} -> {:ok, body}
        nil -> {:ok, "[]"}
      end
    end
  end

  describe "list_assets!/1" do
    test "flattens assets across every release on the first page" do
      body =
        ~s([
          {"tag_name": "v0.2.0", "assets": [{"name": "cache-a.tar.gz", "browser_download_url": "https://x/cache-a.tar.gz"}]},
          {"tag_name": "v0.1.0", "assets": [{"name": "cache-b.tar.gz", "browser_download_url": "https://x/cache-b.tar.gz"}]}
        ])

      fetch = fake_fetch([{"&page=1", body}])

      assert Remote.list_assets!(fetch) == [
               %{name: "cache-a.tar.gz", url: "https://x/cache-a.tar.gz"},
               %{name: "cache-b.tar.gz", url: "https://x/cache-b.tar.gz"}
             ]
    end

    test "pages until a page comes back empty" do
      page1 = release_json([{"cache-1.tar.gz", "https://x/cache-1.tar.gz"}])
      page2 = release_json([{"cache-2.tar.gz", "https://x/cache-2.tar.gz"}])

      fetch = fake_fetch([{"&page=1", page1}, {"&page=2", page2}, {"&page=3", "[]"}])

      assert Remote.list_assets!(fetch) == [
               %{name: "cache-1.tar.gz", url: "https://x/cache-1.tar.gz"},
               %{name: "cache-2.tar.gz", url: "https://x/cache-2.tar.gz"}
             ]
    end

    test "a release with no assets contributes nothing" do
      body = ~s([{"tag_name": "v0.1.0", "assets": []}])
      fetch = fake_fetch([{"&page=1", body}])

      assert Remote.list_assets!(fetch) == []
    end

    test "a fetch failure raises Remote.Error naming the URL" do
      fetch = fake_fetch([{"&page=1", {:error, :timeout}}])

      assert_raise Remote.Error, ~r/releases\?per_page=100&page=1.*timeout/s, fn ->
        Remote.list_assets!(fetch)
      end
    end

    test "a non-list JSON response raises Remote.Error" do
      fetch = fake_fetch([{"&page=1", ~s({"message": "Not Found"})}])

      assert_raise Remote.Error, ~r/expected a list/, fn ->
        Remote.list_assets!(fetch)
      end
    end

    test "unparseable JSON raises Remote.Error" do
      fetch = fake_fetch([{"&page=1", "not json"}])

      assert_raise Remote.Error, ~r/unparseable JSON/, fn ->
        Remote.list_assets!(fetch)
      end
    end
  end

  describe "sync!/3" do
    @tag :tmp_dir
    test "downloads only archives matching type", %{tmp_dir: dir} do
      body =
        release_json([
          {"cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz", "https://x/cache.tar.gz"},
          {"openapi-1.20.3-0.1.0-bbbbbbbbbbbb.tar.gz", "https://x/openapi.tar.gz"}
        ])

      fetch =
        fake_fetch([
          {"&page=1", body},
          {"&page=2", "[]"},
          {"cache.tar.gz", "cache bytes"},
          {"openapi.tar.gz", "openapi bytes"}
        ])

      assert :ok = Remote.sync!(:cache, dir, fetch)

      assert File.ls!(dir) == ["cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz"]
      assert File.read!(Path.join(dir, "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz")) == "cache bytes"
    end

    @tag :tmp_dir
    test "creates the directory when it does not exist", %{tmp_dir: dir} do
      target = Path.join(dir, "nested/registry")
      refute File.dir?(target)

      fetch = fake_fetch([{"&page=1", "[]"}])
      assert :ok = Remote.sync!(:cache, target, fetch)

      assert File.dir?(target)
    end

    @tag :tmp_dir
    test "a file already present is never re-fetched", %{tmp_dir: dir} do
      name = "cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz"
      File.write!(Path.join(dir, name), "already here")

      body = release_json([{name, "https://x/would-blow-up"}])
      # No entry for "would-blow-up" in the fake — an unmatched URL falls
      # through to the fake's own {:ok, "[]"} default, which would overwrite
      # the file below with "[]" if sync! fetched it. The assertion on the
      # file's original content is what actually proves it was skipped.
      fetch = fake_fetch([{"&page=1", body}, {"&page=2", "[]"}])

      assert :ok = Remote.sync!(:cache, dir, fetch)
      assert File.read!(Path.join(dir, name)) == "already here"
    end

    @tag :tmp_dir
    test "a matching prefix that is a different type is not downloaded", %{tmp_dir: dir} do
      # "cache_extra" starts with "cache" but not with "cache-": must not match.
      body = release_json([{"cache_extra-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz", "https://x/y"}])
      fetch = fake_fetch([{"&page=1", body}, {"&page=2", "[]"}])

      assert :ok = Remote.sync!(:cache, dir, fetch)
      assert File.ls!(dir) == []
    end

    @tag :tmp_dir
    test "a download failure raises Remote.Error naming the asset URL", %{tmp_dir: dir} do
      body = release_json([{"cache-1.20.3-0.1.0-aaaaaaaaaaaa.tar.gz", "https://x/cache.tar.gz"}])

      fetch =
        fake_fetch([
          {"&page=1", body},
          {"&page=2", "[]"},
          {"cache.tar.gz", {:error, :closed}}
        ])

      assert_raise Remote.Error, ~r/cache\.tar\.gz.*closed/s, fn ->
        Remote.sync!(:cache, dir, fetch)
      end
    end
  end
end
