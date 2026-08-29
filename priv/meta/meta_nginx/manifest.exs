%{
  deps: [],
  files: [
    {"nginx.conf", :sole_owner},
    {"compose.yaml", :contributes, [key: :nginx_compose]}
  ],
  name: :nginx,
  version: "0.1.0"
}
