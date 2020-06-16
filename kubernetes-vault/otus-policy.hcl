path "otus/otus-ro/*" {
    capabilities = ["read", "list"] 
}
path "otus/otus-rw/*" {
    capabilities = ["read", "create", "update", "list"]
}
