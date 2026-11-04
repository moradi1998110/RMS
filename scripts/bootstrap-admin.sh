#!/usr/bin/env bash
# Creates the very first admin. After that, admins create everyone from the app.
#
# Required: API_URL, SERVICE_ROLE_KEY, ADMIN_USERNAME, ADMIN_FULL_NAME, ADMIN_PASSWORD
# Pass these through the environment. Never commit them.

set -euo pipefail

: "${API_URL:?}" "${SERVICE_ROLE_KEY:?}" "${ADMIN_USERNAME:?}" "${ADMIN_FULL_NAME:?}" "${ADMIN_PASSWORD:?}"

user_id="$(
  jq -n --arg email "$ADMIN_USERNAME@meals.invalid" --arg password "$ADMIN_PASSWORD" \
    '{email: $email, password: $password, email_confirm: true}' |
  curl -sS --fail-with-body "$API_URL/auth/v1/admin/users" \
    -H "apikey: $SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -d @- |
  jq -r '.id'
)"

jq -n --arg id "$user_id" --arg username "$ADMIN_USERNAME" --arg name "$ADMIN_FULL_NAME" \
  '{id: $id, username: $username, full_name: $name, role: "admin", must_change_password: false}' |
curl -sS --fail-with-body "$API_URL/rest/v1/profiles" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d @- > /dev/null

echo "Admin $ADMIN_USERNAME created"
