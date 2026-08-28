defmodule Capstone.Integration.CqrsDispatchTest do
  @moduledoc """
  Exercises the full :cqrs dispatch path against a real, Postgres-backed
  EventStore: a successful create whose projection is visible immediately
  (consistency: :strong), a genuine concurrent race (proving the
  Reservation aggregate's deterministic id + the event store's atomic
  per-stream append serializes it), and a duplicate dispatch after the
  Nebulex cache reservation has been deleted (proving the Reservation
  aggregate, not the cache, is the real ground truth).

  The fixture schema, migration, aggregate, commands, events, Router, and
  projector written here into the GENERATED project are NOT part of
  priv/meta/cqrs_component/ — capstone doesn't know a consuming project's
  domain, so this lives entirely in this repo's own test suite.
  """

  use ExUnit.Case, async: false

  alias Capstone.New.Bootstrap
  alias Capstone.New.Options
  alias Capstone.New.Shell

  setup do
    Mix.Local.append_archives()
    Mix.Task.reenable("new")
    Mix.Task.reenable("phx.new")

    dir = Path.join(System.tmp_dir!(), "cqrs-dispatch-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, tmp_dir: dir}
  end

  @tag :toolchain
  @tag timeout: :timer.minutes(10)
  test "dispatch: success, a concurrent race, and the aggregate catching what the cache no longer blocks",
       %{tmp_dir: tmp} do
    capstone_path = File.cwd!()
    name = "cqrs_dispatch"

    opts = %Options{
      name: name,
      app: :cqrs_dispatch,
      module: CqrsDispatch,
      base: :api,
      github_org: "acme",
      capstone: {:path, capstone_path},
      plugins: [:cqrs]
    }

    File.cd!(tmp, fn -> assert :ok = Bootstrap.run(opts, Bootstrap.defaults()) end)

    project = Path.join(tmp, name)
    write_fixture_test_config!(project)
    write_fixture_migration!(project)
    write_fixture_domain!(project)
    write_fixture_router_wiring!(project)
    write_fixture_test_alias!(project)
    write_fixture_test!(project)

    Shell.cmd!(["test", "test/widget_dispatch_test.exs"], project)
  end

  defp write_fixture_test_config!(project) do
    path = Path.join(project, "config/test.exs")

    File.write!(
      path,
      File.read!(path) <>
        """

        # This integration test specifically needs the real, Postgres-backed
        # EventStore — override :cqrs's InMemory-adapter default (correct for the
        # plugin's own shipped unit tests) for this one throwaway fixture project
        # only. Config merges same-key keyword lists with the later occurrence's
        # leaf values winning, so this correctly overrides just :adapter.
        config :cqrs_dispatch, CqrsDispatch.CQRS.App,
          event_store: [
            adapter: Commanded.EventStore.Adapters.EventStore,
            event_store: CqrsDispatch.EventStore
          ]
        """
    )
  end

  defp write_fixture_test_alias!(project) do
    path = Path.join(project, "mix.exs")
    original = File.read!(path)

    updated =
      String.replace(
        original,
        ~s(test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]),
        ~s(test: [\n        "event_store.drop --quiet -e CqrsDispatch.EventStore",\n        "event_store.create --quiet -e CqrsDispatch.EventStore",\n        "event_store.init --quiet -e CqrsDispatch.EventStore",\n        "ecto.create --quiet",\n        "ecto.migrate --quiet",\n        "test"\n      ])
      )

    if updated == original do
      raise "expected to find the `test:` alias entry in #{path}, but it wasn't there — inspect the file's actual content and adjust the replace pattern"
    end

    File.write!(path, updated)
  end

  defp write_fixture_migration!(project) do
    path = Path.join(project, "priv/repo/migrations/20260828000001_create_widgets.exs")
    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    defmodule CqrsDispatch.Repo.Migrations.CreateWidgets do
      use Ecto.Migration

      def change do
        create table(:widgets, primary_key: false) do
          add :id, :binary_id, primary_key: true
          add :email, :string, null: false

          timestamps(type: :utc_datetime)
        end

        create unique_index(:widgets, [:email])
      end
    end
    """)
  end

  defp write_fixture_domain!(project) do
    File.write!(Path.join(project, "lib/cqrs_dispatch/widgets.ex"), """
    defmodule CqrsDispatch.WidgetRecord do
      use Ecto.Schema

      @primary_key {:id, Uniq.UUID, autogenerate: false, version: 7, type: :binary_id, dump: :default}
      schema "widgets" do
        field :email, :string
        timestamps(type: :utc_datetime)
      end
    end

    defmodule CqrsDispatch.Widgets.Commands.CreateWidget do
      @behaviour CqrsDispatch.CQRS.Command

      @enforce_keys [:id, :email]
      defstruct [:id, :email]

      @impl true
      def build(params), do: %__MODULE__{id: Uniq.UUID.uuid7(), email: params.email}

      @impl true
      def schema_tag, do: :widget

      @impl true
      def unique_fields, do: [[:email]]
    end

    defmodule CqrsDispatch.Widgets.Events.WidgetCreated do
      @derive Jason.Encoder
      @enforce_keys [:id, :email]
      defstruct [:id, :email]
    end

    defmodule CqrsDispatch.Widgets.Widget do
      defstruct [:id, :email]

      alias CqrsDispatch.Widgets.Commands.CreateWidget
      alias CqrsDispatch.Widgets.Events.WidgetCreated

      def execute(%__MODULE__{id: nil}, %CreateWidget{} = cmd) do
        %WidgetCreated{id: cmd.id, email: cmd.email}
      end

      def apply(state, %WidgetCreated{id: id, email: email}) do
        %__MODULE__{state | id: id, email: email}
      end
    end

    defmodule CqrsDispatch.Widgets.Router do
      use Commanded.Commands.Router

      dispatch(CqrsDispatch.Widgets.Commands.CreateWidget,
        to: CqrsDispatch.Widgets.Widget,
        identity: :id
      )
    end

    defmodule CqrsDispatch.Widgets.Projector do
      use Commanded.Event.Handler,
        application: CqrsDispatch.CQRS.App,
        name: "widgets_projector",
        consistency: :strong

      alias CqrsDispatch.Widgets.Events.WidgetCreated

      def handle(%WidgetCreated{id: id, email: email}, _metadata) do
        %CqrsDispatch.WidgetRecord{}
        |> Ecto.Changeset.cast(%{id: id, email: email}, [:id, :email])
        |> CqrsDispatch.Repo.insert()

        :ok
      end
    end
    """)
  end

  defp write_fixture_router_wiring!(project) do
    app_path = Path.join(project, "lib/cqrs_dispatch/cqrs/app.ex")

    File.write!(app_path, """
    defmodule CqrsDispatch.CQRS.App do
      use Commanded.Application, otp_app: :cqrs_dispatch

      router(CqrsDispatch.CQRS.Reservation.Router)
      router(CqrsDispatch.Widgets.Router)
    end
    """)

    application_path = Path.join(project, "lib/cqrs_dispatch/application.ex")
    original = File.read!(application_path)

    updated =
      String.replace(
        original,
        "CqrsDispatch.CQRS.Cache\n    ]",
        "CqrsDispatch.CQRS.Cache,\n      CqrsDispatch.Widgets.Projector\n    ]"
      )

    # String.replace/3 is a no-op (not an error) if the pattern doesn't
    # match — assert the file actually changed, or a whitespace mismatch
    # here would silently leave the Projector unsupervised instead of
    # failing loudly.
    if updated == original do
      raise "expected to find \"CqrsDispatch.CQRS.Cache\\n    ]\" in #{application_path}, but it wasn't there — inspect the file's actual content and adjust the replace pattern"
    end

    File.write!(application_path, updated)
  end

  defp write_fixture_test!(project) do
    File.write!(Path.join(project, "test/widget_dispatch_test.exs"), """
    defmodule CqrsDispatch.WidgetDispatchTest do
      use CqrsDispatch.DataCase, async: false

      alias CqrsDispatch.CQRS.Cache
      alias CqrsDispatch.CQRS.Dispatcher
      alias CqrsDispatch.Widgets.Commands.CreateWidget

      test "a successful create is visible immediately via query" do
        email = "widget-\#{System.unique_integer([:positive])}@example.com"
        assert :ok = Dispatcher.dispatch(CreateWidget, %{email: email})

        widget = CqrsDispatch.Repo.get_by!(CqrsDispatch.WidgetRecord, email: email)
        assert widget.email == email
      end

      test "two concurrent dispatches for the same email: exactly one succeeds" do
        email = "race-\#{System.unique_integer([:positive])}@example.com"

        results =
          [Task.async(fn -> Dispatcher.dispatch(CreateWidget, %{email: email}) end),
           Task.async(fn -> Dispatcher.dispatch(CreateWidget, %{email: email}) end)]
          |> Enum.map(&Task.await(&1, 5_000))

        assert Enum.count(results, &(&1 == :ok)) == 1
        assert Enum.count(results, &match?({:error, _}, &1)) == 1
      end

      test "the Reservation aggregate, not the cache, is the real ground truth" do
        email = "expired-\#{System.unique_integer([:positive])}@example.com"
        assert :ok = Dispatcher.dispatch(CreateWidget, %{email: email})

        # Simulate the cache reservation having expired (or never existed,
        # e.g. after a node restart) — the cache no longer blocks a second
        # attempt, so this proves the Reservation aggregate's own
        # deterministic identity is the actual ground truth, not the cache.
        key = {:widget, [:email], [email]}
        Cache.delete(key, [])

        assert {:error, {:already_taken, [:email]}} = Dispatcher.dispatch(CreateWidget, %{email: email})
      end
    end
    """)
  end
end
