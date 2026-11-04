#!/usr/bin/env bash
# Checks against the live project after a deploy. Prints statuses, never keys.
# Needs: API_URL, SUPABASE_PROJECT_REF, SUPABASE_ACCESS_TOKEN.
#
# This output is published to a branch, so nothing here may ever print a key. Masking
# commands would not help: they print the key to the log file before the runner hides it.

set -u

source "$(dirname "$0")/fetch-keys.sh"

if [ -z "$PUBLISHABLE_KEY" ] || [ -z "$SECRET_KEY" ]; then
  echo "FAIL - could not get the project's API keys"
  exit 1
fi

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

# Reports whether the old key still opens the API, using the value the project lists now.
if [ -z "$LEGACY_SERVICE_KEY" ]; then
  echo "legacy service key: not listed"
else
  echo "legacy service key fingerprint: $(printf '%s' "$LEGACY_SERVICE_KEY" | sha256sum | cut -c1-16)"
  echo "legacy service key answers: $(status_of "$API_URL/storage/v1/bucket/meal-images" \
    -H "apikey: $LEGACY_SERVICE_KEY" -H "Authorization: Bearer $LEGACY_SERVICE_KEY")"
fi

expect "self sign-up is off" "$(status_of "$API_URL/auth/v1/signup" -H "apikey: $PUBLISHABLE_KEY" -H "Content-Type: application/json" \
  -d '{"email":"stranger@meals.invalid","password":"stranger-password"}')" "422"

expect "signed-out visitors cannot read wallets" "$(status_of "$API_URL/rest/v1/wallets?select=held" -H "apikey: $PUBLISHABLE_KEY")" "401"
expect "signed-out visitors cannot read profiles" "$(status_of "$API_URL/rest/v1/profiles?select=id" -H "apikey: $PUBLISHABLE_KEY")" "401"
expect "signed-out visitors cannot book" "$(status_of "$API_URL/rest/v1/rpc/book_meals" -H "apikey: $PUBLISHABLE_KEY" -H "Content-Type: application/json" \
  -d '{"p_offering_ids":[],"p_key":"00000000-0000-0000-0000-000000000000"}')" "401"
expect "signed-out visitors cannot end sessions" "$(status_of "$API_URL/rest/v1/rpc/revoke_user_sessions" -H "apikey: $PUBLISHABLE_KEY" -H "Content-Type: application/json" \
  -d '{"p_user_id":"00000000-0000-0000-0000-000000000000"}')" "401"

for name in create-user reset-password set-user-active; do
  expect "$name is deployed and asks for sign-in" "$(status_of -X POST "$API_URL/functions/v1/$name" -H "apikey: $PUBLISHABLE_KEY")" "401"
done

expect "the secret key can reach the session function" "$(status_of "$API_URL/rest/v1/rpc/revoke_user_sessions" \
  -H "apikey: $SECRET_KEY" -H "Content-Type: application/json" \
  -d '{"p_user_id":"00000000-0000-0000-0000-000000000000"}')" "204"

expect "the meal images bucket exists" "$(status_of "$API_URL/storage/v1/bucket/meal-images" -H "apikey: $SECRET_KEY")" "200"

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All live checks passed"
