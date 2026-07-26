#!/usr/bin/env bash
# Push the admin.vrittiai.com Cloudflare Access service token into Infisical so scripts /
# Postman / CI can pull the CF-Access headers.
#
# The service token is STABLE — its client-id/secret don't rotate once created — so this is a
# one-time push after `tofu apply`. Re-run it only if you rotate the token (Cloudflare) or its
# 1-year duration lapses.
#
# Writes to the project/env in this dir's .infisical.json (infrastructure / prod), path "/".
#
# Just run it — it self-wraps in `infisical run` so both `tofu output` (R2 state-backend creds)
# and `infisical secrets set` have what they need:
#   ./push-admin-token.sh
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$SCRIPT")"

# Re-exec once under infisical run (guarded against an infinite loop) if creds aren't injected.
if [[ -z "${VRITTI_INFISICAL_WRAPPED:-}" ]]; then
  exec infisical run --projectId 8f447810-a5c7-4a83-a4f3-1a775999edd9 --env prod -- \
    env VRITTI_INFISICAL_WRAPPED=1 "$SCRIPT"
fi

CLIENT_ID="$(tofu output -raw admin_service_token_client_id)"
CLIENT_SECRET="$(tofu output -raw admin_service_token_client_secret)"

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
  echo "error: empty token output — run 'infisical run -- tofu apply' first." >&2
  exit 1
fi

# --env / --projectId default to .infisical.json (prod / infrastructure). --path is root.
infisical secrets set \
  "ADMIN_CF_ACCESS_CLIENT_ID=${CLIENT_ID}" \
  "ADMIN_CF_ACCESS_CLIENT_SECRET=${CLIENT_SECRET}"

echo "Pushed ADMIN_CF_ACCESS_CLIENT_ID / ADMIN_CF_ACCESS_CLIENT_SECRET to Infisical (infrastructure/prod)."
