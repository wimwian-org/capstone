# NewApiApp

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## CQRS

`NewApiApp.CQRS.Dispatcher.dispatch/2` runs a command through a real, event-sourced pipeline:
build and validate a command struct, reserve its declared unique-field groups (a fast Nebulex
pre-check, then a race-proof dispatch to an internal `NewApiApp.CQRS.Reservation` aggregate),
then dispatch the real domain command through `NewApiApp.CQRS.App`. `dispatch/2` returns
`:ok | {:error, reason}` — **not** the created struct, since persisting an event and projecting
a read model are decoupled. Fetch the result with `NewApiApp.CQRS.Dispatcher.query/2` after
`:ok`.

### Setup

A real EventStore needs its own Postgres database, separate from the app's normal one — run once
per environment:

```bash
mix event_store.create
mix event_store.init
```

(`config/test.exs` already configures the plugin's own tests and a generated project's default
test suite to use Commanded's in-memory adapter instead — no event store setup needed for `mix
test`.)

### Worked example

A command module implements `NewApiApp.CQRS.Command`, its own aggregate implements Commanded's
`execute/2`/`apply/2` contract, and an event handler projects into your own Ecto schema:

```elixir
# A developer's own aggregate, commands, and events — NOT shipped by this plugin.
defmodule NewApiApp.Widgets.Widget do
  defstruct [:id, :email]
end

defmodule NewApiApp.Widgets.Commands.CreateWidget do
  @behaviour NewApiApp.CQRS.Command

  @enforce_keys [:id, :email]
  defstruct [:id, :email]

  @impl true
  def build(params), do: %__MODULE__{id: Uniq.UUID.uuid7(), email: params.email}

  @impl true
  def schema_tag, do: :widget

  @impl true
  def unique_fields, do: [[:email]]
end

defmodule NewApiApp.Widgets.Commands.UpdateWidget do
  @enforce_keys [:id, :email]
  defstruct [:id, :email]
end

defmodule NewApiApp.Widgets.Events.WidgetCreated do
  @enforce_keys [:id, :email]
  defstruct [:id, :email]
end

defmodule NewApiApp.Widgets.Events.WidgetUpdated do
  @enforce_keys [:id, :email]
  defstruct [:id, :email]
end

defmodule NewApiApp.Widgets.Widget do
  defstruct [:id, :email]

  alias NewApiApp.Widgets.Commands.CreateWidget
  alias NewApiApp.Widgets.Commands.UpdateWidget
  alias NewApiApp.Widgets.Events.WidgetCreated
  alias NewApiApp.Widgets.Events.WidgetUpdated

  def execute(%__MODULE__{id: nil}, %CreateWidget{} = cmd) do
    %WidgetCreated{id: cmd.id, email: cmd.email}
  end

  def execute(%__MODULE__{id: id} = _state, %UpdateWidget{} = cmd) when not is_nil(id) do
    %WidgetUpdated{id: cmd.id, email: cmd.email}
  end

  def apply(state, %WidgetCreated{id: id, email: email}) do
    %__MODULE__{state | id: id, email: email}
  end

  def apply(state, %WidgetUpdated{email: email}) do
    %__MODULE__{state | email: email}
  end
end

defmodule NewApiApp.Widgets.Router do
  use Commanded.Commands.Router

  dispatch([NewApiApp.Widgets.Commands.CreateWidget, NewApiApp.Widgets.Commands.UpdateWidget],
    to: NewApiApp.Widgets.Widget,
    identity: :id
  )
end

# Add this Router to NewApiApp.CQRS.App alongside the shipped Reservation.Router:
#
#   defmodule NewApiApp.CQRS.App do
#     use Commanded.Application, otp_app: :new_api_app
#
#     router(NewApiApp.CQRS.Reservation.Router)
#     router(NewApiApp.Widgets.Router)
#   end

defmodule NewApiApp.Widgets.Projector do
  use Commanded.Event.Handler,
    application: NewApiApp.CQRS.App,
    name: "widgets_projector",
    consistency: :strong

  alias NewApiApp.Widgets.Events.WidgetCreated
  alias NewApiApp.Widgets.Events.WidgetUpdated

  def handle(%WidgetCreated{id: id, email: email}, _metadata) do
    %NewApiApp.Widgets.WidgetRecord{}
    |> Ecto.Changeset.cast(%{id: id, email: email}, [:id, :email])
    |> NewApiApp.Repo.insert()

    :ok
  end

  def handle(%WidgetUpdated{id: id, email: email}, _metadata) do
    NewApiApp.Repo.get!(NewApiApp.Widgets.WidgetRecord, id)
    |> Ecto.Changeset.cast(%{email: email}, [:email])
    |> NewApiApp.Repo.update()

    :ok
  end
end
```

`NewApiApp.Widgets.WidgetRecord` is your own Ecto schema for the projected read model, with a
matching migration declaring `create unique_index(:widgets, [:email])` (no explicit `:name`
needed — `UniqueCheck` doesn't validate a DB constraint directly in this design; the event
store's atomic per-stream append is the race guard, and the DB unique index here is a normal
data-integrity backstop for the read model itself). Use UUIDv7 for your own entity identity:

```elixir
@primary_key {:id, Uniq.UUID, autogenerate: true, version: 7, type: :binary_id, dump: :default}
```

`dump: :default` is required alongside `type: :binary_id`, not decorative: Ecto's Postgres
adapter runs a two-stage dump for `:binary_id` (`[Uniq.UUID, Ecto.UUID]`), and `Ecto.UUID.dump/1`
only accepts the canonical dashed-string form — `Uniq.UUID`'s own default (`dump: :raw`) would
hand it raw bytes instead, and `insert` fails with `Ecto.ChangeError`. Verified against the real
`uniq` and `ecto` package source (traced through `Ecto.Type.adapter_dump/3` and
`Ecto.Adapters.Postgres.dumpers/2`) while building this plugin's own real-Postgres integration
test.

Dispatch a create or an update through the same entry point:

```elixir
:ok = NewApiApp.CQRS.Dispatcher.dispatch(NewApiApp.Widgets.Commands.CreateWidget, %{email: "a@example.com"})
{:ok, widget} = NewApiApp.CQRS.Dispatcher.query(NewApiApp.Widgets.Queries.GetWidget, %{email: "a@example.com"})
```

**Uniqueness on update:** `UniqueCheck` is only invoked by the create path. An update that
changes a previously-reserved unique field does not automatically re-reserve — call
`NewApiApp.CQRS.UniqueCheck.reserve/3` yourself before dispatching such an update, and release
the old reservation, if your domain needs that guarantee.

**Limitation:** event versioning/upcasting strategies for evolving your own event schemas over an
aggregate's lifetime are your own project's concern — this plugin doesn't prescribe one.
