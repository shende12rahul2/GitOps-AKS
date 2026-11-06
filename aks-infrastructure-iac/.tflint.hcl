# TFLint configuration (run with --recursive from the repository root).
# CI installs the azurerm ruleset with `tflint --init` (needs GitHub access).
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "all"
}

plugin "azurerm" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Modules intentionally declare provider requirements without provider blocks.
rule "terraform_unused_required_providers" {
  enabled = false
}
