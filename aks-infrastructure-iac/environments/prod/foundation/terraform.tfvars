project        = "akspoc"
environment    = "prod"
location       = "eastus2"
location_short = "eus2"
owner          = "platform-team"
cost_center    = "prod"

vnet_cidr         = "10.30.0.0/16"
app_dns_zone_name = "poc.example.com"

# Production: public WAF frontend for the application, deterministic egress,
# Bastion Standard for tunnelled admin access, and delete locks.
appgw_public_frontend_enabled   = true
appgw_public_source_prefixes    = ["Internet"]
acr_private_endpoint_enabled    = true
nat_gateway_enabled             = true
bastion_standard_subnet_enabled = true
resource_lock_level             = "CanNotDelete"
