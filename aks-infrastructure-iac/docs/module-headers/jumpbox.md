# jumpbox

Optional administration entry point for the private cluster: Ubuntu 24.04 VM
without a public IP, Entra ID SSH login (`AADSSHLoginForLinux`), trusted launch,
platform patching, nightly auto-shutdown, and Azure Bastion.

| Bastion SKU | Cost | Access |
|---|---|---|
| `Developer` | free | Portal SSH only (CLI administration from the VM) |
| `Standard` | billed hourly | Native client and `az network bastion tunnel` (open the Argo CD/Airflow UIs from a local browser) |

Cloud-init installs the Azure CLI, kubectl, kubelogin, Helm and the Argo CD CLI.
