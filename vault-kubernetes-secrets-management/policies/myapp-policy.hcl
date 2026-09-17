path "secret/data/myapp/*" {
  capabilities = ["read"]
}

path "database/creds/my-role" {
  capabilities = ["read"]
}
