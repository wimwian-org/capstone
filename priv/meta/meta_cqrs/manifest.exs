%{
  deps: [
    "{:nebulex, \"~> 3.0\"}",
    "{:nebulex_local, \"~> 3.0\"}",
    "{:uniq, \"~> 0.6\"}",
    "{:commanded, \"~> 1.4\"}",
    "{:commanded_eventstore_adapter, \"~> 1.4\"}",
    "{:eventstore, \"~> 1.4\"}"
  ],
  files: [
    {"lib/APP/cqrs/app.ex", :sole_owner},
    {"lib/APP/cqrs/cache.ex", :sole_owner},
    {"lib/APP/cqrs/command.ex", :sole_owner},
    {"lib/APP/cqrs/dispatcher.ex", :sole_owner},
    {"lib/APP/cqrs/query.ex", :sole_owner},
    {"lib/APP/cqrs/reservation.ex", :sole_owner},
    {"lib/APP/cqrs/reservation/commands.ex", :sole_owner},
    {"lib/APP/cqrs/reservation/events.ex", :sole_owner},
    {"lib/APP/cqrs/reservation/router.ex", :sole_owner},
    {"lib/APP/cqrs/unique_check.ex", :sole_owner},
    {"lib/APP/event_store.ex", :sole_owner},
    {"test/cqrs/dispatcher_test.exs", :sole_owner},
    {"test/cqrs/reservation_test.exs", :sole_owner},
    {"test/cqrs/unique_check_test.exs", :sole_owner},
    {"README.md", :contributes, [key: :cqrs_readme]},
    {"config/config.exs", :contributes, [key: :cqrs_config, at: :before_import]},
    {"config/test.exs", :contributes, [key: :cqrs_test]},
    {"lib/APP/application.ex", :contributes,
     [
       key: :cqrs_application,
       child: [
         "<%= @module %>.EventStore",
         "<%= @module %>.CQRS.App",
         "<%= @module %>.CQRS.Cache"
       ]
     ]}
  ],
  name: :cqrs,
  version: "0.1.0"
}
