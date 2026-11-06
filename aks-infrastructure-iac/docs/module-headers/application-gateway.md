# application-gateway

Application Gateway v2 (`WAF_v2` or `Standard_v2`) for the AGIC add-on.

- **Private frontend always** (static IP in the gateway subnet). The public
  frontend is optional (`public_frontend_enabled`). A private-only gateway needs
  the `EnableApplicationGatewayNetworkIsolation` subscription feature and the
  subnet delegated to `Microsoft.Network/applicationGateways`.
- **WAF policy**: Microsoft Default Rule Set 2.1 + Bot Manager 1.1, request body
  inspection, per-client-IP rate limiting custom rule, Detection/Prevention mode.
- **TLS policy** `AppGwSslPolicy20220101S` (TLS 1.2+, strong ciphers), HTTP/2.
- **Ownership split**: Terraform owns the gateway (SKU, scale, subnet, frontends,
  TLS policy, WAF association). AGIC owns listeners, rules, pools, probes,
  settings and certificates; those are in `ignore_changes`.
- Access and firewall logs to Log Analytics (resource-specific tables).
