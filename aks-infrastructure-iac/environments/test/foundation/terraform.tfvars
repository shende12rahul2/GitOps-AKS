# Non-secret environment configuration. subscription_id is supplied by the
# pipeline (TF_VAR_subscription_id) or locally via `export TF_VAR_subscription_id=...`.
project        = "akspoc"
environment    = "test"
location       = "eastus2"
location_short = "eus2"
owner          = "platform-team"
cost_center    = "poc"

vnet_cidr         = "10.20.0.0/16"
app_dns_zone_name = "poc.example.com"

appgw_public_frontend_enabled   = false
acr_private_endpoint_enabled    = false
nat_gateway_enabled             = false
bastion_standard_subnet_enabled = false
resource_lock_level             = null
