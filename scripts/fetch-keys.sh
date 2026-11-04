#!/usr/bin/env bash
# Source this to set PUBLISHABLE_KEY and SECRET_KEY for the live project, creating them
# if the project has none. Needs SUPABASE_PROJECT_REF and SUPABASE_ACCESS_TOKEN.
# Sets LEGACY_SERVICE_KEY too when the project still lists one. Never prints a key.

management_api="https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/api-keys"

list_keys() {
  curl -sS --fail-with-body "$management_api?reveal=true" -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN"
}

key_of_type() {
  jq -r --arg type "$1" '[.[] | select(.type == $type)] | (map(select(.name == "default")) + .)[0].api_key // empty' <<< "$keys_json"
}

ensure_key() {
  if [ -z "$(key_of_type "$1")" ]; then
    jq -n --arg type "$1" '{type: $type, name: "default"}' |
      curl -sS --fail-with-body -o /dev/null "$management_api" \
        -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" -d @-
    echo "created the $1 key"
    keys_json="$(list_keys)"
  fi
}

keys_json="$(list_keys)"
ensure_key publishable
ensure_key secret

PUBLISHABLE_KEY="$(key_of_type publishable)"
SECRET_KEY="$(key_of_type secret)"
LEGACY_SERVICE_KEY="$(jq -r '.[] | select(.name == "service_role") | .api_key // empty' <<< "$keys_json")"
unset keys_json
export PUBLISHABLE_KEY SECRET_KEY LEGACY_SERVICE_KEY
