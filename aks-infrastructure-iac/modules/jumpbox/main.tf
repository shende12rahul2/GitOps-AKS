# Optional administration entry point for the private cluster.
#   - Linux VM with no public IP, Entra ID SSH login (no local passwords/keys).
#   - Azure Bastion: Developer SKU (free, portal SSH only) or Standard (native
#     client + `az network bastion tunnel`, needed to open the Argo CD/Airflow UIs
#     from a local browser).
#   - Auto-shutdown every evening to keep the cost near zero.
resource "azurerm_network_interface" "this" {
  name                = "nic-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  name                            = var.name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.vm_size
  network_interface_ids           = [azurerm_network_interface.this.id]
  admin_username                  = "azureadmin"
  disable_password_authentication = true
  encryption_at_host_enabled      = var.encryption_at_host_enabled
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  patch_mode                      = "AutomaticByPlatform"
  patch_assessment_mode           = "AutomaticByPlatform"
  custom_data                     = base64encode(file("${path.module}/cloud-init.yaml"))
  tags                            = var.tags

  # Required by the API, never used: Entra ID login replaces local SSH keys.
  admin_ssh_key {
    username   = "azureadmin"
    public_key = var.bootstrap_ssh_public_key
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  boot_diagnostics {}
}

resource "azurerm_virtual_machine_extension" "entra_login" {
  name                       = "AADSSHLoginForLinux"
  virtual_machine_id         = azurerm_linux_virtual_machine.this.id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADSSHLoginForLinux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  tags                       = var.tags
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "this" {
  virtual_machine_id    = azurerm_linux_virtual_machine.this.id
  location              = var.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = "UTC"
  tags                  = var.tags

  notification_settings {
    enabled = false
  }
}

resource "azurerm_role_assignment" "login" {
  for_each = var.admin_group_object_ids

  scope                = azurerm_linux_virtual_machine.this.id
  role_definition_name = "Virtual Machine Administrator Login"
  principal_id         = each.value
  principal_type       = "Group"
}

resource "azurerm_public_ip" "bastion" {
  count = var.bastion_sku == "Standard" ? 1 : 0

  name                = "pip-bas-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "this" {
  count = var.bastion_sku == null ? 0 : 1

  name                = "bas-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.bastion_sku
  tags                = var.tags

  # Developer SKU: shared infrastructure, attaches to the VNet, no subnet/IP.
  virtual_network_id = var.bastion_sku == "Developer" ? var.virtual_network_id : null

  tunneling_enabled  = var.bastion_sku == "Standard" ? true : null
  ip_connect_enabled = var.bastion_sku == "Standard" ? true : null

  dynamic "ip_configuration" {
    for_each = var.bastion_sku == "Standard" ? [1] : []

    content {
      name                 = "ipconfig"
      subnet_id            = var.bastion_subnet_id
      public_ip_address_id = azurerm_public_ip.bastion[0].id
    }
  }

  lifecycle {
    precondition {
      condition     = var.bastion_sku != "Standard" || var.bastion_subnet_id != null
      error_message = "Bastion Standard needs an AzureBastionSubnet (/26 or larger)."
    }
  }
}
