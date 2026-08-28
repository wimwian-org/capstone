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
    archive_sha256: "6756a65224947e1c48c48bbda0604fc079bb907742e4c870075ecedf58366299",
    derived_from: :api,
    files: %{
      ".formatter.exs" => "a44a43d777033eb6c64e0101b7469611c2def3b377b04c9d6b2a8620a347d385",
      ".gitignore" => "62ee1d39760528ade9087a64430331c1362541232b1213cdae98a25cce8888ed",
      "AGENTS.md" => "00f6f1bdb914d6eb925e9f1abaae89b10fe7b7245323df8e7bdf6c6b65fd31a4",
      "README.md" => "7fa5188001caf7081c06a82e449770f460029c3881ab6d47ff80ef3ffac98963",
      "config/config.exs" => "6a7734a2b5f00eea9206414cb2c72524c86e7da1ca3a9827e6aae218c1eec155",
      "config/dev.exs" => "105066f4897d1acf4ed57806f2fe950010e2898a1216c77203cdb08249872d49",
      "config/prod.exs" => "4d305ac8156d0e4bb49de00f219c7d4ecd553d762d484da994ea598b2e79ba90",
      "config/runtime.exs" => "3f29f4cdd20a6b406ffa68f56108e8966f98e908b31d893a5126818db8a9fb85",
      "config/test.exs" => "a20ca71cf45c0b51a81a452f3263f2711cb7336b67e556376127fe6341d509cf",
      "lib/new_api_app.ex" => "93287d12318850a59c12446b58033095bae63fec79cd58c4eb92c369b0b999fe",
      "lib/new_api_app/application.ex" =>
        "dfd81ddd6c46736e5db861086841be7f2892336f7575511649f141c5a7934842",
      "lib/new_api_app/cache.ex" =>
        "c2382c6552521eaad0a9ec179f4462085641907a7806e4cc25dc1f365e0a9daf",
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
      "mix.exs" => "7a13a47598112a524b1ee88dcf4c76cd51c32e9de75181f3f0f7f14a66bf2585",
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
    tree_digest: "sha256:2852460d5e6fee5bac091c2ba188e1150bcfce42018d9d20eac9bb1bb4c61d2b"
  },
  cqrs: %{
    derived_from: :api,
    names: %{app: "new_api_app", module: "NewApiApp", name: "new_api_app"},
    path: "priv/meta/cqrs_component"
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
  otp: %{
    archive_sha256: "ef77546f3059d2a5f156a494267131ed77a71431eadbc3deb590dd730f52b8d2",
    argv: ["new_otp_app"],
    elixir: "1.20.3",
    erts: "17.0.5",
    files: %{
      ".formatter.exs" => "a46ecd2cb12fd54c0cf0928c72fb10bef329b3f72b49df9bef621c3370734bc5",
      ".gitignore" => "630947e18540e2c5179f6e2ca3c5b9a234e71fea1e0b08a5ba912afa407a2b9f",
      "README.md" => "7f91f940e64c8fdb675d60719c8e8a85b6e9387a991201302f8cb31d8e78a140",
      "lib/new_otp_app.ex" => "d43abbe0e0d84073689a0755404d38ac53ec61dc55600b94e8b27622b9017a94",
      "mix.exs" => "1c3f745db3258e7d6ca1c239554fe815186e54234b3d57c3f7b041a946935e6b",
      "test/new_otp_app_test.exs" =>
        "cecfd52cbd029cd84e46c0a2253498509b3e6403efb3904e4cee9df0e0188b4f",
      "test/test_helper.exs" => "b086ec47f0c6c7aaeb4cffca5ae5243dd05e0dc96ab761ced93325d5315f4b12"
    },
    generator: :mix_new,
    generator_version: "1.20.3",
    normalisations: [],
    otp: "29.0.5",
    path: "priv/meta/baseline_otp",
    tree_digest: "sha256:5357ecb72a5dcb1aa6f43fe2959e03fc0e8cbc0a520b4b53bc7cbc939d7efab8"
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
  }
}
