%{
  api: %{
    archive_sha256: "14da00a3fa2a413b1aa3fcc3449bdf70d35ba981da5811a881255d554cb2d2b2",
    argv: ["new_api_app", "--no-html", "--no-assets", "--no-install", "--no-version-check"],
    elixir: "1.20.3",
    erts: "17.0.5",
    files: %{
      ".formatter.exs" => "a44a43d777033eb6c64e0101b7469611c2def3b377b04c9d6b2a8620a347d385",
      ".gitignore" => "62ee1d39760528ade9087a64430331c1362541232b1213cdae98a25cce8888ed",
      "AGENTS.md" => "00f6f1bdb914d6eb925e9f1abaae89b10fe7b7245323df8e7bdf6c6b65fd31a4",
      "README.md" => "08f794ca41a109f6ff51f85c6b919666a0146fdd64823488dc6de054b3e66103",
      "config/config.exs" => "6a7734a2b5f00eea9206414cb2c72524c86e7da1ca3a9827e6aae218c1eec155",
      "config/dev.exs" => "105066f4897d1acf4ed57806f2fe950010e2898a1216c77203cdb08249872d49",
      "config/prod.exs" => "4d305ac8156d0e4bb49de00f219c7d4ecd553d762d484da994ea598b2e79ba90",
      "config/runtime.exs" => "3f29f4cdd20a6b406ffa68f56108e8966f98e908b31d893a5126818db8a9fb85",
      "config/test.exs" => "a20ca71cf45c0b51a81a452f3263f2711cb7336b67e556376127fe6341d509cf",
      "lib/new_api_app.ex" => "0bbd7d634a418a9abb5fb9f93e53fe0a332ad85b220f1397439b091e1c1a4c02",
      "lib/new_api_app/application.ex" =>
        "dfd81ddd6c46736e5db861086841be7f2892336f7575511649f141c5a7934842",
      "lib/new_api_app/mailer.ex" =>
        "c607a46ffca95ab2e63c5c0c1078b1e9eb2f61640b845526a68bbd84c2e742dc",
      "lib/new_api_app/repo.ex" =>
        "6b171e503d4e1b7734e5e1cc91cfd52219d80dc7a9cd75e73cdf2eebe2db3f24",
      "lib/new_api_app_web.ex" =>
        "d4ded48aa07fd27fc19fb5e082f4959cf9728e44fa08ca1fa96326122473d1f1",
      "lib/new_api_app_web/controllers/error_json.ex" =>
        "ba767ae62030f0f759c245ada6ccb8d865b00ac4a4e4c3d5bce5845e8aaa4d0d",
      "lib/new_api_app_web/endpoint.ex" =>
        "6a730a529c3b812af2929cf33c7df9b3bb53308d5620e8b4a09830261163d42c",
      "lib/new_api_app_web/gettext.ex" =>
        "0606b29e602f87bde9c10670522e2a873d74910cd1f4e915ec6fa9f80c2c1818",
      "lib/new_api_app_web/router.ex" =>
        "18f68f5eec8914616c88bebbe9fa840b59e979c088328163989081269afce4b4",
      "lib/new_api_app_web/telemetry.ex" =>
        "545604fa4abecf9644ca57b1d495f587c9e19884d1d7c1c703dcd6513da7cce6",
      "mix.exs" => "ac9f5ad45500826c9501545e22b2c86d3a1655513eb1587ed4172be9af1eea31",
      "priv/gettext/en/LC_MESSAGES/errors.po" =>
        "7965ec884cd9c0dd4f13b268b485e1e3edc13d8f2574eee6f11b35bf3175d05b",
      "priv/gettext/errors.pot" =>
        "e2ba1a9a3fd94ac18f7d60d8a03fdfcd0c306aa7b34c5c679f10d356fa42d358",
      "priv/repo/migrations/.formatter.exs" =>
        "0214526079b381af52379d2b1fff614512fe4f5bb9a04394ef3246e5b1f61c87",
      "priv/repo/seeds.exs" => "82a007edef590351038659089cc5840ff011c5af7bc38659242922047122b472",
      "priv/static/favicon.ico" =>
        "01723aeae3ce3b5195a8f42e3eb6e9018a8c08b7acda4ed382b31341811f0a8a",
      "priv/static/robots.txt" =>
        "f994bfae2c1db1221ac049f1097776b444048e0b0a7705d33ea511b610bed115",
      "test/new_api_app_web/controllers/error_json_test.exs" =>
        "2af6dd41cde5382eaa3e3ffc7d052596b7334f05cffa911df85419617cd513ff",
      "test/support/conn_case.ex" =>
        "1398686968936337abc0d883180d75fcc8227fb3a5b7d4855161a8e28d8a3c61",
      "test/support/data_case.ex" =>
        "031590471b16158509060d1de434a2640e2e1838ed1f9e0cc7c3ba8fbdde3f4f",
      "test/test_helper.exs" => "70b2e16f8bc7ff44754829b35847cee6522b027df423f7080828f635b0846c9c"
    },
    generator: :phx_new,
    generator_version: "1.8.9",
    names: %{app: "new_api_app", module: "NewApiApp", name: "new_api_app"},
    normalisations: [
      {:secret, "config/config.exs", :signing_salt},
      {:secret, "config/dev.exs", :secret_key_base},
      {:secret, "config/test.exs", :secret_key_base},
      {:secret, "lib/new_api_app_web/endpoint.ex", :signing_salt},
      {:removed, ".git/"}
    ],
    otp: "29.0.5",
    path: "priv/meta/baseline_api",
    tree_digest: "sha256:3459dcc09d6bffe7a67570d65e5227003974628bf7273e63b95cd67f91431f69"
  },
  cache: %{
    archive_sha256: "9cdf5fa1599d1378b40f21fd34a9b37b0afece9cae506e6482c010ec11e900bd",
    derived_from: :api,
    files: %{
      ".formatter.exs" => "a44a43d777033eb6c64e0101b7469611c2def3b377b04c9d6b2a8620a347d385",
      ".gitignore" => "62ee1d39760528ade9087a64430331c1362541232b1213cdae98a25cce8888ed",
      "AGENTS.md" => "00f6f1bdb914d6eb925e9f1abaae89b10fe7b7245323df8e7bdf6c6b65fd31a4",
      "README.md" => "8f67e2ad92bab7614ee5587eadeec09def9ae81b7cbb8245acf196c80028e99c",
      "config/config.exs" => "9d7912d5c4aa81b7458941206bd0dcc733067c47768fd751976c2a2a7417904a",
      "config/dev.exs" => "105066f4897d1acf4ed57806f2fe950010e2898a1216c77203cdb08249872d49",
      "config/prod.exs" => "4d305ac8156d0e4bb49de00f219c7d4ecd553d762d484da994ea598b2e79ba90",
      "config/runtime.exs" => "3f29f4cdd20a6b406ffa68f56108e8966f98e908b31d893a5126818db8a9fb85",
      "config/test.exs" => "a20ca71cf45c0b51a81a452f3263f2711cb7336b67e556376127fe6341d509cf",
      "lib/new_api_app.ex" => "4f36a0b3a63fbf72434e98177f35a6c0e799f719de5ef17d1ad7594178bc0449",
      "lib/new_api_app/application.ex" =>
        "acfde448815b36430b3208ab3965f1d5cbb10651ffb4565aff92604c71c78505",
      "lib/new_api_app/cache.ex" =>
        "318e4ce28cc50b95c8f9b7973e17b793b5dcf8b96bcac30541a65b68495f197d",
      "lib/new_api_app/cache/store.ex" =>
        "19d611332429921fde4092168bbb034635adca7585e23bf89aeeeae167768294",
      "lib/new_api_app/mailer.ex" =>
        "c607a46ffca95ab2e63c5c0c1078b1e9eb2f61640b845526a68bbd84c2e742dc",
      "lib/new_api_app/repo.ex" =>
        "6b171e503d4e1b7734e5e1cc91cfd52219d80dc7a9cd75e73cdf2eebe2db3f24",
      "lib/new_api_app_web.ex" =>
        "d4ded48aa07fd27fc19fb5e082f4959cf9728e44fa08ca1fa96326122473d1f1",
      "lib/new_api_app_web/controllers/error_json.ex" =>
        "ba767ae62030f0f759c245ada6ccb8d865b00ac4a4e4c3d5bce5845e8aaa4d0d",
      "lib/new_api_app_web/endpoint.ex" =>
        "6a730a529c3b812af2929cf33c7df9b3bb53308d5620e8b4a09830261163d42c",
      "lib/new_api_app_web/gettext.ex" =>
        "0606b29e602f87bde9c10670522e2a873d74910cd1f4e915ec6fa9f80c2c1818",
      "lib/new_api_app_web/router.ex" =>
        "18f68f5eec8914616c88bebbe9fa840b59e979c088328163989081269afce4b4",
      "lib/new_api_app_web/telemetry.ex" =>
        "545604fa4abecf9644ca57b1d495f587c9e19884d1d7c1c703dcd6513da7cce6",
      "mix.exs" => "6d005a3b0d1cb2be586c9a960be828c4c94aab3fe033954c4adf04fe1218f96c",
      "priv/gettext/en/LC_MESSAGES/errors.po" =>
        "7965ec884cd9c0dd4f13b268b485e1e3edc13d8f2574eee6f11b35bf3175d05b",
      "priv/gettext/errors.pot" =>
        "e2ba1a9a3fd94ac18f7d60d8a03fdfcd0c306aa7b34c5c679f10d356fa42d358",
      "priv/repo/migrations/.formatter.exs" =>
        "0214526079b381af52379d2b1fff614512fe4f5bb9a04394ef3246e5b1f61c87",
      "priv/repo/seeds.exs" => "82a007edef590351038659089cc5840ff011c5af7bc38659242922047122b472",
      "priv/static/favicon.ico" =>
        "01723aeae3ce3b5195a8f42e3eb6e9018a8c08b7acda4ed382b31341811f0a8a",
      "priv/static/robots.txt" =>
        "f994bfae2c1db1221ac049f1097776b444048e0b0a7705d33ea511b610bed115",
      "test/new_api_app_web/controllers/error_json_test.exs" =>
        "2af6dd41cde5382eaa3e3ffc7d052596b7334f05cffa911df85419617cd513ff",
      "test/support/conn_case.ex" =>
        "1398686968936337abc0d883180d75fcc8227fb3a5b7d4855161a8e28d8a3c61",
      "test/support/data_case.ex" =>
        "031590471b16158509060d1de434a2640e2e1838ed1f9e0cc7c3ba8fbdde3f4f",
      "test/test_helper.exs" => "70b2e16f8bc7ff44754829b35847cee6522b027df423f7080828f635b0846c9c"
    },
    names: %{app: "new_api_app", module: "NewApiApp", name: "new_api_app"},
    normalisations: [
      {:secret, "config/config.exs", :signing_salt},
      {:secret, "config/dev.exs", :secret_key_base},
      {:secret, "config/test.exs", :secret_key_base},
      {:secret, "lib/new_api_app_web/endpoint.ex", :signing_salt}
    ],
    path: "priv/meta/cache_component",
    tree_digest: "sha256:e3c197a333749f149a7b1e0a7a530d41841a6f6f43565762d27f3cabd1e88733"
  },
  cqrs: %{
    archive_sha256: "a7bcc8f298c9473443fb52e88605770d0a9457c18d8bf422596ac67c08f408d8",
    derived_from: :api,
    files: %{
      ".formatter.exs" => "a44a43d777033eb6c64e0101b7469611c2def3b377b04c9d6b2a8620a347d385",
      ".gitignore" => "62ee1d39760528ade9087a64430331c1362541232b1213cdae98a25cce8888ed",
      "AGENTS.md" => "00f6f1bdb914d6eb925e9f1abaae89b10fe7b7245323df8e7bdf6c6b65fd31a4",
      "README.md" => "06a584c7841862c39515ffd9bc649d2f355a2c33be85f65fbce16903de1685f2",
      "config/config.exs" => "136b808c9a34986f898d72e0411ff37ac0627506b8ea22a58b29b63fc9d49931",
      "config/dev.exs" => "105066f4897d1acf4ed57806f2fe950010e2898a1216c77203cdb08249872d49",
      "config/prod.exs" => "4d305ac8156d0e4bb49de00f219c7d4ecd553d762d484da994ea598b2e79ba90",
      "config/runtime.exs" => "3f29f4cdd20a6b406ffa68f56108e8966f98e908b31d893a5126818db8a9fb85",
      "config/test.exs" => "05e0a771602eae47a0d85affc2228f0a2d322cf9f2d794e1753846a3f8b0bb1c",
      "lib/new_api_app.ex" => "0bbd7d634a418a9abb5fb9f93e53fe0a332ad85b220f1397439b091e1c1a4c02",
      "lib/new_api_app/application.ex" =>
        "ed9e99f9e0dcd50b311c909e4b6d6df3d8704e1f18ec8c77fb5e896f73eda626",
      "lib/new_api_app/cqrs/app.ex" =>
        "b4ac1ee7fc62eb6789bdc194629b3e31bde9d7fb67c380c268b1058d89d9c0d3",
      "lib/new_api_app/cqrs/cache.ex" =>
        "7ca94ccb90fadaaa1405d419dd60753e94b9d71c1896520fd4ee077b6a5603a5",
      "lib/new_api_app/cqrs/command.ex" =>
        "417e8c3d57653b67c4b8dcfde280bb645d47efb7612d22833814083710c71429",
      "lib/new_api_app/cqrs/dispatcher.ex" =>
        "786406bbf965c71fc16608eb98730b62395d992121369fe3adfe6bfe14c0881b",
      "lib/new_api_app/cqrs/query.ex" =>
        "1fc8c0813f95852364645c8c87172643e53cc605eacfb81692af2c9c2554cbde",
      "lib/new_api_app/cqrs/reservation.ex" =>
        "9836e5dc246cf8e8fc4dcdda75f46b3eaedfd3314108f8c3a742bc21b72462b9",
      "lib/new_api_app/cqrs/reservation/commands.ex" =>
        "6c304612e8bd957035d879c6dcb847105e21ce6cf914e2c210d74af5da8cba2a",
      "lib/new_api_app/cqrs/reservation/events.ex" =>
        "0b62c1f49efc895f26750b511ae4b4bb560232f9bc49dacf61819c5fc1596828",
      "lib/new_api_app/cqrs/reservation/router.ex" =>
        "85a79141140a71d0bca2f8e950c01a6e7c2aa9c959d88aa367beca78fcf2e3cc",
      "lib/new_api_app/cqrs/unique_check.ex" =>
        "7284c9ea04843103e9087ecf18a3e161ca125139045193360ebc10b0a65ed61b",
      "lib/new_api_app/event_store.ex" =>
        "0c4c12a0dd603adec911364252d90f8796197262e0b4f8c0a8a3ecae43014e02",
      "lib/new_api_app/mailer.ex" =>
        "c607a46ffca95ab2e63c5c0c1078b1e9eb2f61640b845526a68bbd84c2e742dc",
      "lib/new_api_app/repo.ex" =>
        "6b171e503d4e1b7734e5e1cc91cfd52219d80dc7a9cd75e73cdf2eebe2db3f24",
      "lib/new_api_app_web.ex" =>
        "d4ded48aa07fd27fc19fb5e082f4959cf9728e44fa08ca1fa96326122473d1f1",
      "lib/new_api_app_web/controllers/error_json.ex" =>
        "ba767ae62030f0f759c245ada6ccb8d865b00ac4a4e4c3d5bce5845e8aaa4d0d",
      "lib/new_api_app_web/endpoint.ex" =>
        "6a730a529c3b812af2929cf33c7df9b3bb53308d5620e8b4a09830261163d42c",
      "lib/new_api_app_web/gettext.ex" =>
        "0606b29e602f87bde9c10670522e2a873d74910cd1f4e915ec6fa9f80c2c1818",
      "lib/new_api_app_web/router.ex" =>
        "18f68f5eec8914616c88bebbe9fa840b59e979c088328163989081269afce4b4",
      "lib/new_api_app_web/telemetry.ex" =>
        "545604fa4abecf9644ca57b1d495f587c9e19884d1d7c1c703dcd6513da7cce6",
      "mix.exs" => "25dfcb585ed8a1beede018339cc25bfee299653846855e6b7326df5b5550aab1",
      "priv/gettext/en/LC_MESSAGES/errors.po" =>
        "7965ec884cd9c0dd4f13b268b485e1e3edc13d8f2574eee6f11b35bf3175d05b",
      "priv/gettext/errors.pot" =>
        "e2ba1a9a3fd94ac18f7d60d8a03fdfcd0c306aa7b34c5c679f10d356fa42d358",
      "priv/repo/migrations/.formatter.exs" =>
        "0214526079b381af52379d2b1fff614512fe4f5bb9a04394ef3246e5b1f61c87",
      "priv/repo/seeds.exs" => "82a007edef590351038659089cc5840ff011c5af7bc38659242922047122b472",
      "priv/static/favicon.ico" =>
        "01723aeae3ce3b5195a8f42e3eb6e9018a8c08b7acda4ed382b31341811f0a8a",
      "priv/static/robots.txt" =>
        "f994bfae2c1db1221ac049f1097776b444048e0b0a7705d33ea511b610bed115",
      "test/cqrs/dispatcher_test.exs" =>
        "6a4f8683d0071441bd381a33345fe1903ada06c5f6d01c07a053b174846a8edd",
      "test/cqrs/reservation_test.exs" =>
        "4d65ed17dc9692d5a9057e7e3a91a4303a784e151d969a8264a58139a94fc6d7",
      "test/cqrs/unique_check_test.exs" =>
        "41be159a5d1e2632a48025723e60e1345916d71d5b2e0effa41ecf3b3d8db2e6",
      "test/new_api_app_web/controllers/error_json_test.exs" =>
        "2af6dd41cde5382eaa3e3ffc7d052596b7334f05cffa911df85419617cd513ff",
      "test/support/conn_case.ex" =>
        "1398686968936337abc0d883180d75fcc8227fb3a5b7d4855161a8e28d8a3c61",
      "test/support/data_case.ex" =>
        "031590471b16158509060d1de434a2640e2e1838ed1f9e0cc7c3ba8fbdde3f4f",
      "test/test_helper.exs" => "70b2e16f8bc7ff44754829b35847cee6522b027df423f7080828f635b0846c9c"
    },
    names: %{app: "new_api_app", module: "NewApiApp", name: "new_api_app"},
    normalisations: [
      {:secret, "config/config.exs", :signing_salt},
      {:secret, "config/dev.exs", :secret_key_base},
      {:secret, "config/test.exs", :secret_key_base},
      {:secret, "lib/new_api_app_web/endpoint.ex", :signing_salt}
    ],
    path: "priv/meta/cqrs_component",
    tree_digest: "sha256:eee9c6ee61ea50b8ac6792c5898f807c3a2f3c93418be781a5891cac1a21efde"
  },
  grpc: %{
    archive_sha256: "308618ed9a34c41ce4adf897c38d4acf473a10b739c74efafcdd9cc398580d8b",
    derived_from: :api,
    files: %{
      ".formatter.exs" => "a44a43d777033eb6c64e0101b7469611c2def3b377b04c9d6b2a8620a347d385",
      ".gitignore" => "62ee1d39760528ade9087a64430331c1362541232b1213cdae98a25cce8888ed",
      "AGENTS.md" => "00f6f1bdb914d6eb925e9f1abaae89b10fe7b7245323df8e7bdf6c6b65fd31a4",
      "README.md" => "cfe8e531a2b5c990f4bae46447baa2e1886276f17953b52934ccb48b1183f903",
      "config/config.exs" => "3c0b1f0e5cefb4dd30f0496dc186d5515eb2c107d2db52f96ace6f3fa58047d6",
      "config/dev.exs" => "105066f4897d1acf4ed57806f2fe950010e2898a1216c77203cdb08249872d49",
      "config/prod.exs" => "4d305ac8156d0e4bb49de00f219c7d4ecd553d762d484da994ea598b2e79ba90",
      "config/runtime.exs" => "3f29f4cdd20a6b406ffa68f56108e8966f98e908b31d893a5126818db8a9fb85",
      "config/test.exs" => "a20ca71cf45c0b51a81a452f3263f2711cb7336b67e556376127fe6341d509cf",
      "lib/mix/tasks/new_api_app.grpc.gen.cert.ex" =>
        "4aa3e065e8bf1fc80f0f8283df3f95aa6687a246acda07aa1dcfbbd8932a1294",
      "lib/mix/tasks/new_api_app.grpc.gen.ex" =>
        "bf1d81a978247aee04fdde9697e998930599c4e24accce496bd4bab819413269",
      "lib/new_api_app.ex" => "0bbd7d634a418a9abb5fb9f93e53fe0a332ad85b220f1397439b091e1c1a4c02",
      "lib/new_api_app/application.ex" =>
        "cfe7ac26842bf460aa3f766118c2509638af12d3d49189a124a6fb25d10847a4",
      "lib/new_api_app/grpc/client.ex" =>
        "471f6372e8083e4beaa70dc60dd13b5e9de1482dc56601428e84090be0badea7",
      "lib/new_api_app/grpc/credentials.ex" =>
        "0cde112665c7065c5a030c7ab3475d42df3863b594e94cbd81e23860b686b48e",
      "lib/new_api_app/grpc/endpoint.ex" =>
        "08c513def2d389e6abfd4a30e6600245776dc07dda3f8833d39329f8a00a8c66",
      "lib/new_api_app/mailer.ex" =>
        "c607a46ffca95ab2e63c5c0c1078b1e9eb2f61640b845526a68bbd84c2e742dc",
      "lib/new_api_app/repo.ex" =>
        "6b171e503d4e1b7734e5e1cc91cfd52219d80dc7a9cd75e73cdf2eebe2db3f24",
      "lib/new_api_app_web.ex" =>
        "d4ded48aa07fd27fc19fb5e082f4959cf9728e44fa08ca1fa96326122473d1f1",
      "lib/new_api_app_web/controllers/error_json.ex" =>
        "ba767ae62030f0f759c245ada6ccb8d865b00ac4a4e4c3d5bce5845e8aaa4d0d",
      "lib/new_api_app_web/endpoint.ex" =>
        "6a730a529c3b812af2929cf33c7df9b3bb53308d5620e8b4a09830261163d42c",
      "lib/new_api_app_web/gettext.ex" =>
        "0606b29e602f87bde9c10670522e2a873d74910cd1f4e915ec6fa9f80c2c1818",
      "lib/new_api_app_web/router.ex" =>
        "18f68f5eec8914616c88bebbe9fa840b59e979c088328163989081269afce4b4",
      "lib/new_api_app_web/telemetry.ex" =>
        "545604fa4abecf9644ca57b1d495f587c9e19884d1d7c1c703dcd6513da7cce6",
      "mix.exs" => "25840a0f552618761dca88d16a22485bb5573ebc7faae0c127d848351b7c11d9",
      "priv/cert/grpc_selfsigned.pem" =>
        "ec3401b7bad5361fee93b6f43cb6a3f1d9a599c2a93ee3c59a81b438d9479b7b",
      "priv/cert/grpc_selfsigned_key.pem" =>
        "7d883bd29e442e2da753a0d3c90b5d8275e8aa99aa049c12581a03ceb72588dc",
      "priv/gettext/en/LC_MESSAGES/errors.po" =>
        "7965ec884cd9c0dd4f13b268b485e1e3edc13d8f2574eee6f11b35bf3175d05b",
      "priv/gettext/errors.pot" =>
        "e2ba1a9a3fd94ac18f7d60d8a03fdfcd0c306aa7b34c5c679f10d356fa42d358",
      "priv/repo/migrations/.formatter.exs" =>
        "0214526079b381af52379d2b1fff614512fe4f5bb9a04394ef3246e5b1f61c87",
      "priv/repo/seeds.exs" => "82a007edef590351038659089cc5840ff011c5af7bc38659242922047122b472",
      "priv/static/favicon.ico" =>
        "01723aeae3ce3b5195a8f42e3eb6e9018a8c08b7acda4ed382b31341811f0a8a",
      "priv/static/robots.txt" =>
        "f994bfae2c1db1221ac049f1097776b444048e0b0a7705d33ea511b610bed115",
      "test/grpc/client_test.exs" =>
        "5ab852d9a403bff2d15ff2cbe951c83342fc751e504ca56bcfb2d9955b59c098",
      "test/new_api_app_web/controllers/error_json_test.exs" =>
        "2af6dd41cde5382eaa3e3ffc7d052596b7334f05cffa911df85419617cd513ff",
      "test/support/conn_case.ex" =>
        "1398686968936337abc0d883180d75fcc8227fb3a5b7d4855161a8e28d8a3c61",
      "test/support/data_case.ex" =>
        "031590471b16158509060d1de434a2640e2e1838ed1f9e0cc7c3ba8fbdde3f4f",
      "test/test_helper.exs" => "70b2e16f8bc7ff44754829b35847cee6522b027df423f7080828f635b0846c9c"
    },
    names: %{app: "new_api_app", module: "NewApiApp", name: "new_api_app"},
    normalisations: [
      {:secret, "config/config.exs", :signing_salt},
      {:secret, "config/dev.exs", :secret_key_base},
      {:secret, "config/test.exs", :secret_key_base},
      {:secret, "lib/new_api_app_web/endpoint.ex", :signing_salt}
    ],
    path: "priv/meta/grpc_component",
    tree_digest: "sha256:9ff36b9171688ad77824c2bba5b3aabfcb8317a01b9c89493e6a927296a4a1a9"
  },
  openapi: %{
    archive_sha256: "92c66ce84c9731d95bf3d9ae98882e89d0fe3ffd605d4024acd5f62e98b013c7",
    derived_from: :api,
    files: %{
      ".formatter.exs" => "a44a43d777033eb6c64e0101b7469611c2def3b377b04c9d6b2a8620a347d385",
      ".gitignore" => "62ee1d39760528ade9087a64430331c1362541232b1213cdae98a25cce8888ed",
      "AGENTS.md" => "00f6f1bdb914d6eb925e9f1abaae89b10fe7b7245323df8e7bdf6c6b65fd31a4",
      "README.md" => "08f794ca41a109f6ff51f85c6b919666a0146fdd64823488dc6de054b3e66103",
      "compose.yaml" => "782a76048be7fb51c0d2f30684b06893d2199a1a75fecb9d6be880c5ebcbf0f2",
      "config/config.exs" => "6a7734a2b5f00eea9206414cb2c72524c86e7da1ca3a9827e6aae218c1eec155",
      "config/dev.exs" => "105066f4897d1acf4ed57806f2fe950010e2898a1216c77203cdb08249872d49",
      "config/prod.exs" => "4d305ac8156d0e4bb49de00f219c7d4ecd553d762d484da994ea598b2e79ba90",
      "config/runtime.exs" => "3f29f4cdd20a6b406ffa68f56108e8966f98e908b31d893a5126818db8a9fb85",
      "config/test.exs" => "a20ca71cf45c0b51a81a452f3263f2711cb7336b67e556376127fe6341d509cf",
      "lib/new_api_app.ex" => "0bbd7d634a418a9abb5fb9f93e53fe0a332ad85b220f1397439b091e1c1a4c02",
      "lib/new_api_app/application.ex" =>
        "dfd81ddd6c46736e5db861086841be7f2892336f7575511649f141c5a7934842",
      "lib/new_api_app/mailer.ex" =>
        "c607a46ffca95ab2e63c5c0c1078b1e9eb2f61640b845526a68bbd84c2e742dc",
      "lib/new_api_app/repo.ex" =>
        "6b171e503d4e1b7734e5e1cc91cfd52219d80dc7a9cd75e73cdf2eebe2db3f24",
      "lib/new_api_app_web.ex" =>
        "d4ded48aa07fd27fc19fb5e082f4959cf9728e44fa08ca1fa96326122473d1f1",
      "lib/new_api_app_web/api_spec.ex" =>
        "66eddeb0e2735c6be41352568a0127a38017b45e0694b5e012c87c3eaf9902c1",
      "lib/new_api_app_web/controllers/error_json.ex" =>
        "ba767ae62030f0f759c245ada6ccb8d865b00ac4a4e4c3d5bce5845e8aaa4d0d",
      "lib/new_api_app_web/controllers/health_controller.ex" =>
        "40b3b8dfc97d5effaec94464ce5f6c3123b461aa7089090fa09df408d0d21875",
      "lib/new_api_app_web/endpoint.ex" =>
        "6a730a529c3b812af2929cf33c7df9b3bb53308d5620e8b4a09830261163d42c",
      "lib/new_api_app_web/gettext.ex" =>
        "0606b29e602f87bde9c10670522e2a873d74910cd1f4e915ec6fa9f80c2c1818",
      "lib/new_api_app_web/router.ex" =>
        "3c202c0dd539e73b71cc00e893b2fb5dc1e6cd04841256d4b3a2ee5f97a4c2dd",
      "lib/new_api_app_web/schemas.ex" =>
        "6b49291dccf4fab84c018b4ebf3f3b126f020a73a0627be88688c9ed6455083d",
      "lib/new_api_app_web/telemetry.ex" =>
        "545604fa4abecf9644ca57b1d495f587c9e19884d1d7c1c703dcd6513da7cce6",
      "mix.exs" => "b768f14d89600ba400a72f96b6c74ab0f6a160e993939ff9d0ce9739ed43ef73",
      "priv/gettext/en/LC_MESSAGES/errors.po" =>
        "7965ec884cd9c0dd4f13b268b485e1e3edc13d8f2574eee6f11b35bf3175d05b",
      "priv/gettext/errors.pot" =>
        "e2ba1a9a3fd94ac18f7d60d8a03fdfcd0c306aa7b34c5c679f10d356fa42d358",
      "priv/repo/migrations/.formatter.exs" =>
        "0214526079b381af52379d2b1fff614512fe4f5bb9a04394ef3246e5b1f61c87",
      "priv/repo/seeds.exs" => "82a007edef590351038659089cc5840ff011c5af7bc38659242922047122b472",
      "priv/static/favicon.ico" =>
        "01723aeae3ce3b5195a8f42e3eb6e9018a8c08b7acda4ed382b31341811f0a8a",
      "priv/static/robots.txt" =>
        "f994bfae2c1db1221ac049f1097776b444048e0b0a7705d33ea511b610bed115",
      "test/new_api_app_web/controllers/error_json_test.exs" =>
        "2af6dd41cde5382eaa3e3ffc7d052596b7334f05cffa911df85419617cd513ff",
      "test/support/conn_case.ex" =>
        "1398686968936337abc0d883180d75fcc8227fb3a5b7d4855161a8e28d8a3c61",
      "test/support/data_case.ex" =>
        "031590471b16158509060d1de434a2640e2e1838ed1f9e0cc7c3ba8fbdde3f4f",
      "test/test_helper.exs" => "70b2e16f8bc7ff44754829b35847cee6522b027df423f7080828f635b0846c9c"
    },
    names: %{app: "new_api_app", module: "NewApiApp", name: "new_api_app"},
    normalisations: [
      {:secret, "config/config.exs", :signing_salt},
      {:secret, "config/dev.exs", :secret_key_base},
      {:secret, "config/test.exs", :secret_key_base},
      {:secret, "lib/new_api_app_web/endpoint.ex", :signing_salt}
    ],
    path: "priv/meta/openapi_component",
    tree_digest: "sha256:ccf353c50e96d6fa37bd6f092078157229c6b17637cb36760819a8299f471c06"
  },
  prod_image_api: %{
    archive_sha256: "d3e1d647bbe8d610582113c6290cbb4cf802f7432e21c00caf590229ba7216ab",
    derived_from: :api,
    files: %{
      ".dockerignore" => "96ef59dfd23e25d21295fa16a72846fa536d35bd43f09df5218929e93798ba92",
      ".formatter.exs" => "a44a43d777033eb6c64e0101b7469611c2def3b377b04c9d6b2a8620a347d385",
      ".gitignore" => "62ee1d39760528ade9087a64430331c1362541232b1213cdae98a25cce8888ed",
      "AGENTS.md" => "00f6f1bdb914d6eb925e9f1abaae89b10fe7b7245323df8e7bdf6c6b65fd31a4",
      "Dockerfile" => "d6393a12eea0bfc0b5627d9548235e9ef30b69933139a02a177261e2f59f0cf1",
      "README.md" => "08f794ca41a109f6ff51f85c6b919666a0146fdd64823488dc6de054b3e66103",
      "config/config.exs" => "6a7734a2b5f00eea9206414cb2c72524c86e7da1ca3a9827e6aae218c1eec155",
      "config/dev.exs" => "105066f4897d1acf4ed57806f2fe950010e2898a1216c77203cdb08249872d49",
      "config/prod.exs" => "4d305ac8156d0e4bb49de00f219c7d4ecd553d762d484da994ea598b2e79ba90",
      "config/runtime.exs" => "3f29f4cdd20a6b406ffa68f56108e8966f98e908b31d893a5126818db8a9fb85",
      "config/test.exs" => "a20ca71cf45c0b51a81a452f3263f2711cb7336b67e556376127fe6341d509cf",
      "lib/new_api_app.ex" => "0bbd7d634a418a9abb5fb9f93e53fe0a332ad85b220f1397439b091e1c1a4c02",
      "lib/new_api_app/application.ex" =>
        "dfd81ddd6c46736e5db861086841be7f2892336f7575511649f141c5a7934842",
      "lib/new_api_app/mailer.ex" =>
        "c607a46ffca95ab2e63c5c0c1078b1e9eb2f61640b845526a68bbd84c2e742dc",
      "lib/new_api_app/release.ex" =>
        "3ad6ea1bc511bb2f90b4426ed7cfd0854615f659a514436c20afac26edc70bcf",
      "lib/new_api_app/repo.ex" =>
        "6b171e503d4e1b7734e5e1cc91cfd52219d80dc7a9cd75e73cdf2eebe2db3f24",
      "lib/new_api_app_web.ex" =>
        "d4ded48aa07fd27fc19fb5e082f4959cf9728e44fa08ca1fa96326122473d1f1",
      "lib/new_api_app_web/controllers/error_json.ex" =>
        "ba767ae62030f0f759c245ada6ccb8d865b00ac4a4e4c3d5bce5845e8aaa4d0d",
      "lib/new_api_app_web/endpoint.ex" =>
        "6a730a529c3b812af2929cf33c7df9b3bb53308d5620e8b4a09830261163d42c",
      "lib/new_api_app_web/gettext.ex" =>
        "0606b29e602f87bde9c10670522e2a873d74910cd1f4e915ec6fa9f80c2c1818",
      "lib/new_api_app_web/router.ex" =>
        "18f68f5eec8914616c88bebbe9fa840b59e979c088328163989081269afce4b4",
      "lib/new_api_app_web/telemetry.ex" =>
        "545604fa4abecf9644ca57b1d495f587c9e19884d1d7c1c703dcd6513da7cce6",
      "mix.exs" => "ac9f5ad45500826c9501545e22b2c86d3a1655513eb1587ed4172be9af1eea31",
      "priv/gettext/en/LC_MESSAGES/errors.po" =>
        "7965ec884cd9c0dd4f13b268b485e1e3edc13d8f2574eee6f11b35bf3175d05b",
      "priv/gettext/errors.pot" =>
        "e2ba1a9a3fd94ac18f7d60d8a03fdfcd0c306aa7b34c5c679f10d356fa42d358",
      "priv/repo/migrations/.formatter.exs" =>
        "0214526079b381af52379d2b1fff614512fe4f5bb9a04394ef3246e5b1f61c87",
      "priv/repo/seeds.exs" => "82a007edef590351038659089cc5840ff011c5af7bc38659242922047122b472",
      "priv/static/favicon.ico" =>
        "01723aeae3ce3b5195a8f42e3eb6e9018a8c08b7acda4ed382b31341811f0a8a",
      "priv/static/robots.txt" =>
        "f994bfae2c1db1221ac049f1097776b444048e0b0a7705d33ea511b610bed115",
      "rel/overlays/bin/migrate" =>
        "fba0c83cb1d222c4b92feba184dfeed42b11b093bf1e79b165783ad19870cdb2",
      "rel/overlays/bin/migrate.bat" =>
        "4f84b070072a2c569013aaf32f2915f44429dcda848aed38153d84bb9a7b2512",
      "rel/overlays/bin/server" =>
        "4d79f7f90072e470279cf7824d631f293ae276a3ffbf0c93c22847a90d36f26c",
      "rel/overlays/bin/server.bat" =>
        "a59af8825b9c83cb56cc19fcbcd76709d46f632c793ce882335ffc81e1bb2daa",
      "test/new_api_app_web/controllers/error_json_test.exs" =>
        "2af6dd41cde5382eaa3e3ffc7d052596b7334f05cffa911df85419617cd513ff",
      "test/support/conn_case.ex" =>
        "1398686968936337abc0d883180d75fcc8227fb3a5b7d4855161a8e28d8a3c61",
      "test/support/data_case.ex" =>
        "031590471b16158509060d1de434a2640e2e1838ed1f9e0cc7c3ba8fbdde3f4f",
      "test/test_helper.exs" => "70b2e16f8bc7ff44754829b35847cee6522b027df423f7080828f635b0846c9c"
    },
    names: %{app: "new_api_app", module: "NewApiApp", name: "new_api_app"},
    normalisations: [
      {:secret, "config/config.exs", :signing_salt},
      {:secret, "config/dev.exs", :secret_key_base},
      {:secret, "config/test.exs", :secret_key_base},
      {:secret, "lib/new_api_app_web/endpoint.ex", :signing_salt},
      {:removed, ".git/"}
    ],
    path: "priv/meta/prod_image_api_component",
    tree_digest: "sha256:32f90697087995e7072ff150fc9eeeef6c5268b541cd7052fe69b13e1dd12402"
  },
  web: %{
    archive_sha256: "6a1b8b2adbac7f9b9262a73993cc671eadf765d69f4c0fb9b2de6351873985f7",
    derived_from: :api,
    files: %{
      ".formatter.exs" => "a44a43d777033eb6c64e0101b7469611c2def3b377b04c9d6b2a8620a347d385",
      ".gitignore" => "4cdd262a44895c63946480e41c0e3b6a7641f3ff3c5addf945939c372bcd5550",
      "AGENTS.md" => "00f6f1bdb914d6eb925e9f1abaae89b10fe7b7245323df8e7bdf6c6b65fd31a4",
      "README.md" => "4cdf357e2bede6a315e121cbdb5a4f3bb8eebe49f0d6938a39627f788257fbc3",
      "assets/.prettierignore" =>
        "70c178cc94aabc9ee7a348bd3b12d1f3acdc73eea7d914c516d00c6998c37c88",
      "assets/.prettierrc" => "cbca90e8341ff1103f4c7d1f3fbd2a97f18f528f2bf350968344368970380350",
      "assets/css/app.css" => "8d9cfcd1486a79010567f4bf8b208323c50e26a7775383abcbe7b33f08ee69bb",
      "assets/css/theme.css" =>
        "9c3fe3ecc158b9a98baf384f777cd51ef217898514c7bc126f8edc2f36c26a2a",
      "assets/eslint.config.js" =>
        "dfd9399bd705ce59d268176c0308dd3c216615032f878b291eb95fba9d2fefd5",
      "assets/js/app.js" => "fc800117b537ab479215a561dc808803babf94125851f01f0062a6e7aed4d179",
      "assets/package.json" => "fc5af3fd8fe7854720e408c86e9143d3709bb0fe9a256eef2324f5a97bd35ec3",
      "assets/pnpm-lock.yaml" =>
        "8b3d0a870ea9584b6f6634a933d18ef735c349db28dcd9abe62761bb525c1f24",
      "assets/pnpm-workspace.yaml" =>
        "68b189b6f1924b17118d6d7d5a705315bddc5bd8e88215cde05299e297f62ab4",
      "assets/svelte/components/AppShell.svelte" =>
        "fe66e8c070b3304af02377e9f6ba93e8e24a173f91635c1c9234150a8aa6ae88",
      "assets/svelte/lib/sv5ui.js" =>
        "0b50b94b679b146c1780c9f79ad24c697c6c90a3d005a1383d278ccdd36da3a5",
      "assets/test/svelte/components/AppShell.svelte.test.js" =>
        "de5354cf8633d13f27eb81f8fa53da58fe855533dd00446de7a3afb1f696f25d",
      "assets/tsconfig.json" =>
        "e13e43af231fff9cd3ab20dfe2967d9d055223c0ebe1e0f39dd06065ac269e95",
      "assets/vite.config.mjs" =>
        "2a90c7dd073559fecad7d569cfc21e27dd5fc5e09ce08d12d6503eb330d5ca08",
      "assets/vitest.config.js" =>
        "c35f4a4dc01ae0e51d647eaad2ddc5e004959c5daaa5284c4656b65112fc297b",
      "config/config.exs" => "cc9f90642af69ac8edf358b69847f9b5d5111a0e27c1875297a03f3aecbca3df",
      "config/dev.exs" => "3a657aeb6c3b737a964d81fd6c4e5da8f3971fc3a598fcaad3e2521c7f2d4073",
      "config/prod.exs" => "07c97c8bf8d0f25d228a43bc5e29e6810c3bca916a92ff2856921ab7311230b1",
      "config/runtime.exs" => "1ac8d997f3e1a8e93cf8fcbbd9b231b0700754c5863b79c1758a9e044a023d9a",
      "config/test.exs" => "3739e532b1a21186f3d9c4f3bc18939d6b2c3f2a6313a6e88ed4c1c8324c0c53",
      "lib/mix/tasks/assets.pnpm.ex" =>
        "3264c97a484fd5aa840d16303c069d7d19f30913e65f6d19192b9ace567e1751",
      "lib/new_web_app.ex" => "f164602028041d30db532c01c94865d10fb9f49717ab11d28e16a646c75d6271",
      "lib/new_web_app/application.ex" =>
        "6cae0f6bba0fc15f4e31ef245b6dbc8416e3f68a4e6d7611d82f4bfb4f5fce88",
      "lib/new_web_app/mailer.ex" =>
        "c0641882430eae98a096474129557ff4d9afd31fca29aca444a4482e009a747e",
      "lib/new_web_app/repo.ex" =>
        "3412c81ccbe9d2eade79cef05fb33422a26a18204a87f82e66915122e3d21fee",
      "lib/new_web_app/vite_watcher.ex" =>
        "2d160275040c658e6be84b8710dd0f5695deef4e2f6e080f22f7df33bf71e1a6",
      "lib/new_web_app_web.ex" =>
        "2ca7778838facb4ac57ffb036f800647a963852758efa090d0227917755497db",
      "lib/new_web_app_web/components/core_components.ex" =>
        "3d506e1dc5b23f7cad2b47263c13037acf1218542771ffd1e8cc49068d870eeb",
      "lib/new_web_app_web/components/layouts.ex" =>
        "45b3f4347169fcf198efe81a90f43988b7242a7178d566264051fc77e14a6562",
      "lib/new_web_app_web/components/layouts/root.html.heex" =>
        "1562c2780ea1f86b4452690db4e1c6ab6cc65a1fad4c11c0b78227e9553950f5",
      "lib/new_web_app_web/controllers/error_json.ex" =>
        "d98672d55199f0169a10683f007146333161ac5c16c403ae38ba77fa9bfbfb4c",
      "lib/new_web_app_web/endpoint.ex" =>
        "47bf089c2654e23239c32e2f9afb1bb94b3d0eab1cfa9fccb96cd66ca7709a0f",
      "lib/new_web_app_web/gettext.ex" =>
        "d5f447a109176f46e90ceb06a0acba8a6c350a5e99c1ab956ad3a927154e1557",
      "lib/new_web_app_web/router.ex" =>
        "d840a8a3d12fc05810ec708ce9f2c8cfbd51bcc64347ab9b2afc131b1afbc0f4",
      "lib/new_web_app_web/telemetry.ex" =>
        "19e8995167cd7d1d8e2713b649e9f4edae7c0308158d4bfb5da33a656995b573",
      "mix.exs" => "a79df76b12d85e647942954a3fa5ef1d7caf89c52bad2240afd6c0b4ce930d51",
      "priv/gettext/en/LC_MESSAGES/errors.po" =>
        "7965ec884cd9c0dd4f13b268b485e1e3edc13d8f2574eee6f11b35bf3175d05b",
      "priv/gettext/errors.pot" =>
        "e2ba1a9a3fd94ac18f7d60d8a03fdfcd0c306aa7b34c5c679f10d356fa42d358",
      "priv/repo/migrations/.formatter.exs" =>
        "0214526079b381af52379d2b1fff614512fe4f5bb9a04394ef3246e5b1f61c87",
      "priv/repo/seeds.exs" => "1fea5d1f886a2e9af459b3834ac67f356e934d4bc608dc3f276993f7589679d2",
      "priv/static/favicon.ico" =>
        "01723aeae3ce3b5195a8f42e3eb6e9018a8c08b7acda4ed382b31341811f0a8a",
      "priv/static/robots.txt" =>
        "f994bfae2c1db1221ac049f1097776b444048e0b0a7705d33ea511b610bed115",
      "test/mix/tasks/assets.pnpm_test.exs" =>
        "9deac64c1d5515d2a1cf44db5ad9f32f6ab146f4466945953ea2b289385fad7b",
      "test/new_web_app/vite_watcher_test.exs" =>
        "feb98f987017ab15ac3e29cc3e99429a63a3f781b8478d2783e2848b4378eee0",
      "test/new_web_app_web/controllers/error_json_test.exs" =>
        "551f363303dedb31ee368506f7449d83d4b81f9c68da657c624a264192ba901f",
      "test/support/conn_case.ex" =>
        "7a1269617c77d8cc074cd73a3f32805247b2384cb4ad52f765b4f39eb87629fa",
      "test/support/data_case.ex" =>
        "a153d3adc5dd577088679b41c77ec6ea5cb40ebcc83248747bc26ff9a42d6f9e",
      "test/test_helper.exs" => "3fb183b5fb43ca2e448c1e693571149690de59f71937c0c7165b21654cb525cf"
    },
    names: %{app: "new_web_app", module: "NewWebApp", name: "new_web_app"},
    normalisations: [
      {:secret, "config/config.exs", :signing_salt},
      {:secret, "config/dev.exs", :secret_key_base},
      {:secret, "config/test.exs", :secret_key_base},
      {:secret, "lib/new_web_app_web/endpoint.ex", :signing_salt}
    ],
    path: "priv/meta/baseline_web",
    plugin: :web_layer,
    tree_digest: "sha256:2721cf416f3609823374666b4107f2ff54a4edacc919c41f75004d5c70ae49b4"
  },
  web_layer: %{
    archive_sha256: "70a1514f6f60cbf473cdfa78ee0ebe7f9c233a4673cd1b1882d4079abf116374",
    derived_from: :api,
    files: %{
      ".formatter.exs" => "a44a43d777033eb6c64e0101b7469611c2def3b377b04c9d6b2a8620a347d385",
      ".gitignore" => "2d725c450b234b4a1dc0cc844820343cd127d358c2f19378a902c4d895ed676c",
      "AGENTS.md" => "00f6f1bdb914d6eb925e9f1abaae89b10fe7b7245323df8e7bdf6c6b65fd31a4",
      "README.md" => "a4e392e7af485571bf52f9ca6a419448110ff2b3249a73ae3f4aa5052b08d7d6",
      "assets/.prettierignore" =>
        "70c178cc94aabc9ee7a348bd3b12d1f3acdc73eea7d914c516d00c6998c37c88",
      "assets/.prettierrc" => "cbca90e8341ff1103f4c7d1f3fbd2a97f18f528f2bf350968344368970380350",
      "assets/css/app.css" => "8e835bfd1f34c16315055a93a76c734b9c829d8646608b5ef041eef2dccf8f69",
      "assets/css/theme.css" =>
        "9c3fe3ecc158b9a98baf384f777cd51ef217898514c7bc126f8edc2f36c26a2a",
      "assets/eslint.config.js" =>
        "dfd9399bd705ce59d268176c0308dd3c216615032f878b291eb95fba9d2fefd5",
      "assets/js/app.js" => "fc800117b537ab479215a561dc808803babf94125851f01f0062a6e7aed4d179",
      "assets/package.json" => "73f9d36d6fe899622c75f3bd529c63cebc5345e848fc65ff1e2f2d1b520da603",
      "assets/pnpm-lock.yaml" =>
        "8b3d0a870ea9584b6f6634a933d18ef735c349db28dcd9abe62761bb525c1f24",
      "assets/pnpm-workspace.yaml" =>
        "68b189b6f1924b17118d6d7d5a705315bddc5bd8e88215cde05299e297f62ab4",
      "assets/svelte/components/AppShell.svelte" =>
        "fe66e8c070b3304af02377e9f6ba93e8e24a173f91635c1c9234150a8aa6ae88",
      "assets/svelte/lib/sv5ui.js" =>
        "0b50b94b679b146c1780c9f79ad24c697c6c90a3d005a1383d278ccdd36da3a5",
      "assets/test/svelte/components/AppShell.svelte.test.js" =>
        "de5354cf8633d13f27eb81f8fa53da58fe855533dd00446de7a3afb1f696f25d",
      "assets/tsconfig.json" =>
        "e13e43af231fff9cd3ab20dfe2967d9d055223c0ebe1e0f39dd06065ac269e95",
      "assets/vite.config.mjs" =>
        "2a90c7dd073559fecad7d569cfc21e27dd5fc5e09ce08d12d6503eb330d5ca08",
      "assets/vitest.config.js" =>
        "c35f4a4dc01ae0e51d647eaad2ddc5e004959c5daaa5284c4656b65112fc297b",
      "config/config.exs" => "84df99ba2f7c6b71a2a1473756ec4248b2d4cc68226c9a665ae250cdc923079a",
      "config/dev.exs" => "e238758d7899f15a95752f95f112ef51e666969d0062e4b7415a58f1b2fb8ed6",
      "config/prod.exs" => "4d305ac8156d0e4bb49de00f219c7d4ecd553d762d484da994ea598b2e79ba90",
      "config/runtime.exs" => "3f29f4cdd20a6b406ffa68f56108e8966f98e908b31d893a5126818db8a9fb85",
      "config/test.exs" => "a20ca71cf45c0b51a81a452f3263f2711cb7336b67e556376127fe6341d509cf",
      "lib/mix/tasks/assets.pnpm.ex" =>
        "3264c97a484fd5aa840d16303c069d7d19f30913e65f6d19192b9ace567e1751",
      "lib/new_api_app.ex" => "0bbd7d634a418a9abb5fb9f93e53fe0a332ad85b220f1397439b091e1c1a4c02",
      "lib/new_api_app/application.ex" =>
        "dfd81ddd6c46736e5db861086841be7f2892336f7575511649f141c5a7934842",
      "lib/new_api_app/mailer.ex" =>
        "c607a46ffca95ab2e63c5c0c1078b1e9eb2f61640b845526a68bbd84c2e742dc",
      "lib/new_api_app/repo.ex" =>
        "6b171e503d4e1b7734e5e1cc91cfd52219d80dc7a9cd75e73cdf2eebe2db3f24",
      "lib/new_api_app/vite_watcher.ex" =>
        "8ac50a808c5ab386ccc0b126838bd60a416baa96da2cccc4d8d3ab3291a3cdc2",
      "lib/new_api_app_web.ex" =>
        "5318dd9a01aad452816b0361510f9b141bd607d01075e3ade926a3ee0e043e7d",
      "lib/new_api_app_web/components/core_components.ex" =>
        "61a088575a119417bbe754f251d0a025cdaf7be8607e0bf9ac57cf39d90ac0d9",
      "lib/new_api_app_web/components/layouts.ex" =>
        "960e810f4325681355df9d836ab8f6022b677f3410d0ed7c3d90d59b649b51ae",
      "lib/new_api_app_web/components/layouts/root.html.heex" =>
        "642ba8ed12f5c7d09a2a238cd043bc6f4e6fab5a987042670007ff5df1f47cbe",
      "lib/new_api_app_web/controllers/error_json.ex" =>
        "ba767ae62030f0f759c245ada6ccb8d865b00ac4a4e4c3d5bce5845e8aaa4d0d",
      "lib/new_api_app_web/endpoint.ex" =>
        "30d54eadcd8e152d18973dcd4962933bf3971598f9abb25060b46504d80ad9e6",
      "lib/new_api_app_web/gettext.ex" =>
        "0606b29e602f87bde9c10670522e2a873d74910cd1f4e915ec6fa9f80c2c1818",
      "lib/new_api_app_web/router.ex" =>
        "ec062d547df442a899ab96af2902741b96eb6fea219d315f044428306510d372",
      "lib/new_api_app_web/telemetry.ex" =>
        "545604fa4abecf9644ca57b1d495f587c9e19884d1d7c1c703dcd6513da7cce6",
      "mix.exs" => "91897039bd5c9e025b7279ce0baf2c558faad66d468afc3ccdade28b6dce6b58",
      "priv/gettext/en/LC_MESSAGES/errors.po" =>
        "7965ec884cd9c0dd4f13b268b485e1e3edc13d8f2574eee6f11b35bf3175d05b",
      "priv/gettext/errors.pot" =>
        "e2ba1a9a3fd94ac18f7d60d8a03fdfcd0c306aa7b34c5c679f10d356fa42d358",
      "priv/repo/migrations/.formatter.exs" =>
        "0214526079b381af52379d2b1fff614512fe4f5bb9a04394ef3246e5b1f61c87",
      "priv/repo/seeds.exs" => "82a007edef590351038659089cc5840ff011c5af7bc38659242922047122b472",
      "priv/static/favicon.ico" =>
        "01723aeae3ce3b5195a8f42e3eb6e9018a8c08b7acda4ed382b31341811f0a8a",
      "priv/static/robots.txt" =>
        "f994bfae2c1db1221ac049f1097776b444048e0b0a7705d33ea511b610bed115",
      "test/mix/tasks/assets.pnpm_test.exs" =>
        "9deac64c1d5515d2a1cf44db5ad9f32f6ab146f4466945953ea2b289385fad7b",
      "test/new_api_app/vite_watcher_test.exs" =>
        "5fe6ce50ef5d4bebde61b605e113c5abcd4f1d2bf0681196f46cbce55e51909e",
      "test/new_api_app_web/controllers/error_json_test.exs" =>
        "2af6dd41cde5382eaa3e3ffc7d052596b7334f05cffa911df85419617cd513ff",
      "test/support/conn_case.ex" =>
        "1398686968936337abc0d883180d75fcc8227fb3a5b7d4855161a8e28d8a3c61",
      "test/support/data_case.ex" =>
        "031590471b16158509060d1de434a2640e2e1838ed1f9e0cc7c3ba8fbdde3f4f",
      "test/test_helper.exs" => "70b2e16f8bc7ff44754829b35847cee6522b027df423f7080828f635b0846c9c"
    },
    names: %{app: "new_api_app", module: "NewApiApp", name: "new_api_app"},
    normalisations: [
      {:secret, "config/config.exs", :signing_salt},
      {:secret, "config/dev.exs", :secret_key_base},
      {:secret, "config/test.exs", :secret_key_base},
      {:secret, "lib/new_api_app_web/endpoint.ex", :signing_salt}
    ],
    path: "priv/meta/web_component",
    tree_digest: "sha256:6aa97b83636ccb07edea81e8dbf0d9db8e220308e0e1dec97e2dd030a458872d"
  }
}
