# Secrets consumed in-cluster through the Key Vault CSI driver. Each is readable
# only by the workload identities listed in reader_principal_ids (secret-scoped RBAC).
#
# Generated values use `random_*` resources so they are stable across applies.
# They are sensitive in Terraform state, which is protected (Entra-only, private
# container, versioning, per-environment RBAC).

resource "random_password" "internal_api_key" {
  length  = 48
  special = false
}

resource "random_password" "airflow_db" {
  length  = 40
  special = false # used inside a connection URI
}

resource "random_bytes" "airflow_fernet" {
  length = 32
}

resource "random_password" "airflow_api_secret_key" {
  length  = 48
  special = false
}

resource "random_password" "airflow_webserver_secret_key" {
  length  = 48
  special = false
}

resource "random_password" "airflow_jwt_secret" {
  length  = 64
  special = false
}

locals {
  kv_name = local.platform.key_vault_name
  kv_rg   = local.platform.resource_group_name

  airflow_db_user = "airflow"
  airflow_db_name = "airflow_metadata"

  # Secret values are kept apart from the for_each map: for_each must not depend
  # on sensitive values.
  managed_secret_values = {
    "internal-api-key"            = random_password.internal_api_key.result
    "airflow-db-password"         = random_password.airflow_db.result
    "airflow-metadata-connection" = "postgresql://${local.airflow_db_user}:${random_password.airflow_db.result}@${module.postgresql.fqdn}:5432/${local.airflow_db_name}?sslmode=require"
    # Kombu Redis transport over TLS (port 10000). Airflow sets ssl_cert_reqs=CERT_REQUIRED
    # from [celery] ssl_active=True. The access-key user has no username.
    "airflow-broker-url" = "rediss://:${urlencode(module.redis.primary_access_key)}@${module.redis.hostname}:${module.redis.port}/0"
    # Fernet keys are 32 bytes, URL-safe base64 encoded.
    "airflow-fernet-key"     = replace(replace(random_bytes.airflow_fernet.base64, "+", "-"), "/", "_")
    "airflow-api-secret-key" = random_password.airflow_api_secret_key.result
    "airflow-jwt-secret"     = random_password.airflow_jwt_secret.result
    # Flask/FAB session signing key (AIRFLOW__WEBSERVER__SECRET_KEY).
    "airflow-webserver-secret-key" = random_password.airflow_webserver_secret_key.result
  }

  managed_secrets = {
    "internal-api-key" = {
      content_type = "text/plain"
      readers = {
        frontend             = local.wi["frontend"].principal_id
        user-service         = local.wi["user-service"].principal_id
        product-service      = local.wi["product-service"].principal_id
        order-service        = local.wi["order-service"].principal_id
        notification-service = local.wi["notification-service"].principal_id
        airflow              = local.wi["airflow"].principal_id
      }
    }
    "airflow-db-password" = {
      content_type = "text/plain"
      readers      = { db-bootstrap = local.wi["db-bootstrap"].principal_id }
    }
    "airflow-metadata-connection" = {
      content_type = "application/x-connection-string"
      readers      = { airflow = local.wi["airflow"].principal_id }
    }
    "airflow-broker-url" = {
      content_type = "application/x-connection-string"
      readers      = { airflow = local.wi["airflow"].principal_id }
    }
    "airflow-fernet-key" = {
      content_type = "text/plain"
      readers      = { airflow = local.wi["airflow"].principal_id }
    }
    "airflow-api-secret-key" = {
      content_type = "text/plain"
      readers      = { airflow = local.wi["airflow"].principal_id }
    }
    "airflow-jwt-secret" = {
      content_type = "text/plain"
      readers      = { airflow = local.wi["airflow"].principal_id }
    }
    "airflow-webserver-secret-key" = {
      content_type = "text/plain"
      readers      = { airflow = local.wi["airflow"].principal_id }
    }
  }

  # Values set by an operator after the first apply (scripts/set-operator-secret.sh).
  operator_secrets = {
    "airflow-gitsync-ssh-key" = {
      content_type = "application/x-ssh-key"
      readers      = { airflow = local.wi["airflow"].principal_id }
    }
    "airflow-oauth-client-secret" = {
      content_type = "text/plain"
      readers      = { airflow = local.wi["airflow"].principal_id }
    }
    # Read-only deploy key for a private GitOps repository. Only platform
    # administrators (Key Vault Secrets Officer) read it, during Argo CD bootstrap.
    "argocd-repo-ssh-key" = {
      content_type = "application/x-ssh-key"
      readers      = {}
    }
  }
}

module "secret" {
  source   = "../../../modules/key-vault-secret"
  for_each = local.managed_secrets

  key_vault_name                = local.kv_name
  key_vault_resource_group_name = local.kv_rg
  secret_name                   = each.key
  value                         = local.managed_secret_values[each.key]
  content_type                  = each.value.content_type
  reader_principal_ids          = each.value.readers
  tags                          = { managed_by = "terraform" }
}

module "operator_secret" {
  source   = "../../../modules/key-vault-secret"
  for_each = local.operator_secrets

  key_vault_name                = local.kv_name
  key_vault_resource_group_name = local.kv_rg
  secret_name                   = each.key
  value                         = "PLACEHOLDER-set-by-operator"
  content_type                  = each.value.content_type
  operator_managed              = true
  reader_principal_ids          = each.value.readers
  tags                          = { managed_by = "operator" }
}
