#!/usr/bin/env bash
# Read-only checks against the live project after a deploy. Prints statuses, never keys.
# Needs: API_URL, SUPABASE_PROJECT_REF, SUPABASE_ACCESS_TOKEN.

set -u

keys="$(supabase projects api-keys --project-ref "$SUPABASE_PROJECT_REF" -o json)"
ANON_KEY="$(jq -r '.[] | select(.name == "anon") | .api_key' <<< "$keys")"
SERVICE_ROLE_KEY="$(jq -r '.[] | select(.name == "service_role") | .api_key' <<< "$keys")"
echo "::add-mask::$ANON_KEY"
echo "::add-mask::$SERVICE_ROLE_KEY"

failures=0

expect() {
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1 (expected '$3', got '$2')"
    failures=$((failures + 1))
  fi
}

status_of() {
  curl -sS -o /dev/null -w '%{http_code}' "$@"
}

expect "self sign-up is off" "$(status_of "$API_URL/auth/v1/signup" -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"stranger@meals.invalid","password":"stranger-password"}')" "422"

expect "signed-out visitors cannot read wallets" "$(status_of "$API_URL/rest/v1/wallets?select=held" -H "apikey: $ANON_KEY")" "401"
expect "signed-out visitors cannot read profiles" "$(status_of "$API_URL/rest/v1/profiles?select=id" -H "apikey: $ANON_KEY")" "401"
expect "signed-out visitors cannot book" "$(status_of "$API_URL/rest/v1/rpc/book_meals" -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"p_offering_ids":[],"p_key":"00000000-0000-0000-0000-000000000000"}')" "401"
expect "signed-out visitors cannot end sessions" "$(status_of "$API_URL/rest/v1/rpc/revoke_user_sessions" -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"p_user_id":"00000000-0000-0000-0000-000000000000"}')" "401"

for name in create-user reset-password set-user-active; do
  expect "$name is deployed and asks for sign-in" "$(status_of -X POST "$API_URL/functions/v1/$name" -H "apikey: $ANON_KEY")" "401"
done

expect "the service role can reach the session function" "$(status_of "$API_URL/rest/v1/rpc/revoke_user_sessions" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H "Content-Type: application/json" \
  -d '{"p_user_id":"00000000-0000-0000-0000-000000000000"}')" "204"

expect "the meal images bucket exists" "$(status_of "$API_URL/storage/v1/bucket/meal-images" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY")" "200"

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All live checks passed"
