#!/usr/bin/env bash
# Functional smoke test through the HTTPS entry point (Phase 10). Run from a
# host inside the VNet (jumpbox) or anywhere the private DNS zone resolves.
#   ./smoke-test.sh https://app.poc.example.com [ca-bundle.pem]
set -euo pipefail
base="${1:?https://app.<zone>}"; ca="${2:-}"
curl_() { curl -sS --fail-with-body ${ca:+--cacert "$ca"} "$@"; }
echo "HTTP -> HTTPS redirect: $(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' ${ca:+--cacert "$ca"} "${base/https:/http:}/")"
echo "HSTS: $(curl_ -sI "$base/" | grep -i strict-transport-security | tr -d '\r')"
curl_ "$base/" | grep -q "AKS POC Shop" && echo "frontend: OK"
for api in users products orders notifications; do
  echo "/api/$api -> $(curl_ -o /dev/null -w '%{http_code}' "$base/api/$api")"
done
pid=$(curl_ "$base/api/products" | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["id"])')
curl_ -o /dev/null "$base/api/products/$pid"
echo "Redis cache on 2nd read: $(curl_ -sI "$base/api/products/$pid" | grep -i x-cache | tr -d '\r')"
echo "cache stats: $(curl_ "$base/api/products/cache/stats")"
echo "unauthenticated write rejected: $(curl -s -o /dev/null -w '%{http_code}' ${ca:+--cacert "$ca"} -X POST "$base/api/users" -H 'content-type: application/json' -d '{"email":"x@example.com","full_name":"x"}')"
