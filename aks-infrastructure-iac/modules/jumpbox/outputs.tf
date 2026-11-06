output "vm_id" {
  description = "Jumpbox VM ID."
  value       = azurerm_linux_virtual_machine.this.id
}

output "private_ip_address" {
  description = "Jumpbox private IP."
  value       = azurerm_network_interface.this.private_ip_address
}

output "bastion_name" {
  description = "Bastion host name (null when disabled)."
  value       = try(azurerm_bastion_host.this[0].name, null)
}
