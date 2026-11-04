#!/usr/bin/env bash
# End-to-end test of accounts against a running local stack: real sign-in, real Edge
# Functions. Commits data, so run it only on a throwaway database. Needs curl, jq and
# `supabase functions serve` running. Passwords are never printed.

set -u

eval "$(supabase status -o env | grep -E '^(API_URL|ANON_KEY|SERVICE_ROLE_KEY)=')"
export API_URL SERVICE_ROLE_KEY

failures=0

expect() {
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1 (expected '$3', got '$2')"
    failures=$((failures + 1))
  fi
}

random_password() {
  head -c 18 /dev/urandom | base64 | tr -d '/+='
}

# Prints the session JSON; empty access_token means the sign-in was refused.
login() {
  jq -n --arg email "$1@meals.invalid" --arg password "$2" '{email: $email, password: $password}' |
    curl -sS "$API_URL/auth/v1/token?grant_type=password" \
      -H "apikey: $ANON_KEY" -H "Content-Type: application/json" -d @-
}

token_of() {
  login "$1" "$2" | jq -r '.access_token // empty'
}

can_login() {
  if [ -n "$(token_of "$1" "$2")" ]; then echo yes; else echo no; fi
}

# fn <name> <token or empty> <json>: sets STATUS and BODY.
fn() {
  local auth=()
  [ -n "$2" ] && auth=(-H "Authorization: Bearer $2")
  local response
  response="$(curl -sS -w '\n%{http_code}' "$API_URL/functions/v1/$1" \
    -H "Content-Type: application/json" "${auth[@]}" -d "$3")"
  STATUS="$(tail -n1 <<< "$response")"
  BODY="$(sed '$d' <<< "$response")"
}

# rest <token> <method> <path> [json]: sets STATUS and BODY.
rest() {
  local data=()
  [ "$#" -ge 4 ] && data=(-d "$4")
  local response
  response="$(curl -sS -w '\n%{http_code}' -X "$2" "$API_URL/rest/v1/$3" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $1" \
    -H "Content-Type: application/json" -H "Prefer: return=representation" "${data[@]}")"
  STATUS="$(tail -n1 <<< "$response")"
  BODY="$(sed '$d' <<< "$response")"
}

echo "# First admin"
admin_password="$(random_password)"
ADMIN_USERNAME=acct-admin ADMIN_FULL_NAME="First Admin" ADMIN_PASSWORD="$admin_password" bash scripts/bootstrap-admin.sh
admin_token="$(token_of acct-admin "$admin_password")"
expect "the first admin can sign in" "$([ -n "$admin_token" ] && echo yes || echo no)" "yes"

echo "# Nobody can register alone"
signup_status="$(curl -sS -o /dev/null -w '%{http_code}' "$API_URL/auth/v1/signup" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"stranger@meals.invalid","password":"stranger-password"}')"
expect "self sign-up is refused" "$signup_status" "422"

echo "# Admin creates the organisation"
rest "$admin_token" POST sites '{"name":"Accounts Site"}'
expect "admin adds a site" "$STATUS" "201"
site_id="$(jq -r '.[0].id' <<< "$BODY")"
rest "$admin_token" POST restaurants "$(jq -n --arg s "$site_id" '{site_id: $s, name: "Accounts Restaurant", timezone: "Asia/Baghdad"}')"
expect "admin adds a restaurant" "$STATUS" "201"
restaurant_id="$(jq -r '.[0].id' <<< "$BODY")"

echo "# Creating users"
employee_json="$(jq -n --arg r "$restaurant_id" '{username: "Acct-Emp", full_name: "Test Employee", department: "Nursing", role: "employee", restaurant_id: $r}')"

fn create-user "" "$employee_json"
expect "no sign-in, no account" "$STATUS" "401"
fn create-user "not-a-token" "$employee_json"
expect "a fake token is refused" "$STATUS" "401"

fn create-user "$admin_token" '{"username":"a b","full_name":"x","role":"employee"}'
expect "a bad username is refused" "$(jq -r .error <<< "$BODY")" "invalid_username"
fn create-user "$admin_token" '{"username":"acct-x","full_name":"x","role":"employee"}'
expect "an employee needs a restaurant" "$(jq -r .error <<< "$BODY")" "restaurant_required"
fn create-user "$admin_token" "$(jq -n '{username: "acct-x", full_name: "x", role: "employee", restaurant_id: "00000000-0000-0000-0000-000000000000"}')"
expect "an unknown restaurant is refused" "$(jq -r .error <<< "$BODY")" "restaurant_not_found"
fn create-user "$admin_token" '{"username":"acct-x","full_name":"x","role":"owner"}'
expect "an unknown role is refused" "$(jq -r .error <<< "$BODY")" "invalid_role"

fn create-user "$admin_token" "$employee_json"
expect "admin creates an employee" "$STATUS" "201"
expect "the username is stored in lower case" "$(jq -r .username <<< "$BODY")" "acct-emp"
employee_id="$(jq -r .id <<< "$BODY")"
temp_password="$(jq -r .temporary_password <<< "$BODY")"
expect "a temporary password is issued" "${#temp_password}" "10"

fn create-user "$admin_token" "$employee_json"
expect "a duplicate username is refused" "$(jq -r .error <<< "$BODY")" "username_taken"

fn create-user "$admin_token" "$(jq -n --arg r "$restaurant_id" '{username: "acct-mgr", full_name: "Test Manager", role: "manager", restaurant_id: $r}')"
expect "admin creates a manager" "$STATUS" "201"
manager_id="$(jq -r .id <<< "$BODY")"
manager_password="$(jq -r .temporary_password <<< "$BODY")"

echo "# The employee signs in"
session="$(login acct-emp "$temp_password")"
employee_token="$(jq -r '.access_token // empty' <<< "$session")"
employee_refresh="$(jq -r '.refresh_token // empty' <<< "$session")"
expect "the employee signs in with the temporary password" "$([ -n "$employee_token" ] && echo yes || echo no)" "yes"

rest "$employee_token" GET "profiles?select=role,must_change_password,department&id=eq.$employee_id"
expect "the profile asks for a new password" "$(jq -r '.[0].must_change_password' <<< "$BODY")" "true"
expect "the department is stored" "$(jq -r '.[0].department' <<< "$BODY")" "Nursing"
rest "$employee_token" GET "wallets?select=available,held"
expect "the employee has an empty wallet" "$(jq -c '.[0]' <<< "$BODY")" '{"available":0,"held":0}'

manager_token="$(token_of acct-mgr "$manager_password")"

echo "# Only admins manage accounts"
for caller in "$employee_token" "$manager_token"; do
  fn create-user "$caller" '{"username":"acct-y","full_name":"y","role":"admin"}'
  expect "non-admin cannot create users" "$STATUS" "403"
  fn reset-password "$caller" "$(jq -n --arg id "$employee_id" '{user_id: $id}')"
  expect "non-admin cannot reset passwords" "$STATUS" "403"
  fn set-user-active "$caller" "$(jq -n --arg id "$employee_id" '{user_id: $id, is_active: false}')"
  expect "non-admin cannot deactivate users" "$STATUS" "403"
done

rest "$admin_token" PATCH "profiles?id=eq.$employee_id" '{"username":"renamed"}'
expect "a username cannot be changed directly, even by an admin" "$STATUS" "403"
rest "$admin_token" PATCH "profiles?id=eq.$employee_id" '{"is_active":false}'
expect "deactivation cannot bypass the function" "$STATUS" "403"
rest "$employee_token" PATCH "profiles?id=eq.$employee_id" '{"must_change_password":false}'
expect "an employee cannot clear the flag directly" "$STATUS" "403"

echo "# Meal images"
# upload <token> <folder> <file> <content type>: prints the HTTP status.
upload() {
  curl -sS -o /dev/null -w '%{http_code}' -X POST "$API_URL/storage/v1/object/meal-images/$2/$(basename "$3")" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $1" -H "Content-Type: $4" --data-binary "@$3"
}
image_dir="$(mktemp -d)"
head -c 2048 /dev/urandom > "$image_dir/meal.webp"
head -c 2048 /dev/urandom > "$image_dir/notes.txt"
head -c 400000 /dev/urandom > "$image_dir/huge.webp"

expect "a manager uploads to their own restaurant" "$(upload "$manager_token" "$restaurant_id" "$image_dir/meal.webp" image/webp)" "200"
public_status="$(curl -sS -o /dev/null -w '%{http_code}' "$API_URL/storage/v1/object/public/meal-images/$restaurant_id/meal.webp")"
expect "the image opens by its link" "$public_status" "200"

refused() {
  if [ "$1" = "200" ]; then echo allowed; else echo refused; fi
}
expect "a manager cannot upload to another restaurant" "$(refused "$(upload "$manager_token" "$site_id" "$image_dir/meal.webp" image/webp)")" "refused"
expect "an employee cannot upload" "$(refused "$(upload "$employee_token" "$restaurant_id" "$image_dir/notes.txt" image/webp)")" "refused"
expect "only images are accepted" "$(refused "$(upload "$manager_token" "$restaurant_id" "$image_dir/notes.txt" text/plain)")" "refused"
expect "an oversized image is refused" "$(refused "$(upload "$manager_token" "$restaurant_id" "$image_dir/huge.webp" image/webp)")" "refused"
rm -rf "$image_dir"

echo "# Changing the password"
new_password="$(random_password)"
change_status="$(jq -n --arg password "$new_password" '{password: $password}' |
  curl -sS -o /dev/null -w '%{http_code}' -X PUT "$API_URL/auth/v1/user" \
    -H "apikey: $ANON_KEY" -H "Authorization: Bearer $employee_token" \
    -H "Content-Type: application/json" -d @-)"
expect "the employee sets a new password" "$change_status" "200"
rest "$employee_token" POST "rpc/mark_password_changed" '{}'
rest "$employee_token" GET "profiles?select=must_change_password&id=eq.$employee_id"
expect "the flag clears" "$(jq -r '.[0].must_change_password' <<< "$BODY")" "false"
expect "the temporary password stops working" "$(can_login acct-emp "$temp_password")" "no"
expect "the new password works" "$(can_login acct-emp "$new_password")" "yes"

echo "# Resetting a password"
session="$(login acct-emp "$new_password")"
employee_refresh="$(jq -r '.refresh_token // empty' <<< "$session")"

fn reset-password "$admin_token" '{"user_id":"00000000-0000-0000-0000-000000000000"}'
expect "resetting an unknown user is refused" "$STATUS" "404"
fn reset-password "$admin_token" "$(jq -n --arg id "$employee_id" '{user_id: $id}')"
expect "admin resets the password" "$STATUS" "200"
temp_password="$(jq -r .temporary_password <<< "$BODY")"
expect "the old password stops working" "$(can_login acct-emp "$new_password")" "no"

refresh_status="$(jq -n --arg token "$employee_refresh" '{refresh_token: $token}' |
  curl -sS -o /dev/null -w '%{http_code}' "$API_URL/auth/v1/token?grant_type=refresh_token" \
    -H "apikey: $ANON_KEY" -H "Content-Type: application/json" -d @-)"
expect "a lost phone can no longer renew its session" "$refresh_status" "400"

employee_token="$(token_of acct-emp "$temp_password")"
rest "$employee_token" GET "profiles?select=must_change_password&id=eq.$employee_id"
expect "a new password is asked for again" "$(jq -r '.[0].must_change_password' <<< "$BODY")" "true"

echo "# Deactivating"
admin_id="$(jq -r '.user.id' <<< "$(login acct-admin "$admin_password")")"
fn set-user-active "$admin_token" "$(jq -n --arg id "$admin_id" '{user_id: $id, is_active: false}')"
expect "an admin cannot deactivate themselves" "$(jq -r .error <<< "$BODY")" "cannot_deactivate_self"

fn set-user-active "$admin_token" "$(jq -n --arg id "$employee_id" '{user_id: $id, is_active: false}')"
expect "admin deactivates the employee" "$STATUS" "200"
expect "a deactivated user cannot sign in" "$(can_login acct-emp "$temp_password")" "no"

rest "$employee_token" POST "rpc/book_meals" '{"p_offering_ids":["00000000-0000-0000-0000-000000000000"],"p_key":"00000000-0000-0000-0000-000000000001"}'
expect "a token still in hand cannot book" "$(jq -r .message <<< "$BODY")" "forbidden"

rest "$admin_token" GET "wallets?select=employee_id&employee_id=eq.$employee_id"
expect "the wallet is kept" "$(jq -r 'length' <<< "$BODY")" "1"

fn set-user-active "$admin_token" "$(jq -n --arg id "$employee_id" '{user_id: $id, is_active: true}')"
expect "admin reactivates the employee" "$STATUS" "200"
expect "the employee can sign in again" "$(can_login acct-emp "$temp_password")" "yes"

echo "# Audit trail"
rest "$admin_token" GET "audit_log?select=action,details&entity_id=eq.$employee_id"
expect "every action is recorded" "$(jq -r '[.[].action] | sort | join(",")' <<< "$BODY")" "activate_user,create_user,deactivate_user,reset_password"
case "$BODY" in
  *"$temp_password"*) expect "passwords stay out of the audit log" "found" "absent" ;;
  *) expect "passwords stay out of the audit log" "absent" "absent" ;;
esac

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All account checks passed"
