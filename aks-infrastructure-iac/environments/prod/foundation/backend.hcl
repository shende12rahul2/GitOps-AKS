# Non-secret backend settings. Authentication is Entra ID (OIDC in CI, az login locally).
resource_group_name  = "rg-akspoc-tfstate-eus2"
storage_account_name = "REPLACE_WITH_STATE_ACCOUNT"
container_name       = "tfstate-prod"
key                  = "foundation.tfstate"
use_azuread_auth     = true
