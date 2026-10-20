#!/bin/bash
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/base-test.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/runtime/bin"
ln -s "$ROOT/bin/monarch-i18n" "$test_tmp/runtime/bin/monarch-i18n"
export INDICATOR_TEST="$test_tmp" MONARCH_PATH="$test_tmp/runtime" MONARCH_LANGUAGE=en
export PATH="$test_tmp/runtime/bin:$PATH"
cat > "$test_tmp/runtime/bin/monarch-update-available" <<'EOF'
#!/bin/bash
[[ $* == '--all --json' ]] || exit 99
count=$(cat "$INDICATOR_TEST/count" 2>/dev/null || echo 0)
((count += 1))
echo "$count" > "$INDICATOR_TEST/count"
sed -n "${count}p" "$INDICATOR_TEST/states"
exit "$(sed -n "${count}p" "$INDICATOR_TEST/codes")"
EOF
cat > "$test_tmp/runtime/bin/sleep" <<'EOF'
#!/bin/bash
echo "$1" >> "$INDICATOR_TEST/sleeps"
if (( $(cat "$INDICATOR_TEST/count") >= $(wc -l < "$INDICATOR_TEST/states") )); then
  kill -TERM "$PPID"
fi
EOF
chmod +x "$test_tmp/runtime/bin/"{sleep,monarch-update-available}
cat > "$test_tmp/runtime/bin/nmcli" <<'EOF'
#!/bin/bash
[[ $* == '-t -f STATE,CONNECTIVITY general' && $LC_ALL == "C" ]] || exit 99
printf '%s\n' 'connected:full'
EOF
chmod +x "$test_tmp/runtime/bin/nmcli"

run_stream() {
  rm -f "$test_tmp/count" "$test_tmp/sleeps"
  local code=0
  bash "$ROOT/default/noctalia/indicators/monarch-update.sh" > "$test_tmp/output" || code=$?
  ((code == 143)) || fail "stream did not finish the fixture"
}

jq -cn '{status:"available",count:3,complete:true,aur:1,counts:{monarch:1,repo:1,aur:1},packages:[
  {name:"aur-tool",category:"aur",installed:"1",available:"2"},
  {name:"linux",category:"repo",installed:"6.1",available:"6.2"},
  {name:"monarch",category:"monarch",installed:"2026.10.0",available:"2026.10.1"}]}' > "$test_tmp/states"
echo 0 > "$test_tmp/codes"
run_stream
jq -e '.text == " 3" and .textColor == "primary" and
  (.tooltip | contains("Monarch: 1 · Repositories: 1 · AUR: 1")) and
  (.tooltip | contains("monarch  2026.10.0 → 2026.10.1")) and
  (.tooltip | index("monarch  ") < index("linux  ")) and
  (.tooltip | index("linux  ") < index("aur-tool  "))' "$test_tmp/output" >/dev/null
pass "Monarch takes priority and the tooltip orders categories and shows both versions"

cp "$test_tmp/states" "$test_tmp/mixed"
for category in repo aur; do
  jq -c --arg category "$category" '.packages |= map(select(.category == $category)) |
    .count=1 | .counts={monarch:0,repo:0,aur:0} | .counts[$category]=1 |
    .aur=(if $category == "aur" then 1 else 0 end)' "$test_tmp/mixed" > "$test_tmp/states"
  run_stream
  color=secondary
  [[ $category != "aur" ]] || color=tertiary
  jq -e --arg color "$color" '.textColor == $color and .text == " 1"' "$test_tmp/output" >/dev/null
done
pass "repository and AUR-only upgrades use distinct theme roles"

jq -c '.complete=false | .count=2 | .aur=null | .counts.aur=null |
  .packages |= map(select(.category != "aur"))' "$test_tmp/mixed" > "$test_tmp/states"
run_stream
jq -e '.text == " ≥2" and (.tooltip | contains("AUR: not checked")) and
  (.tooltip | contains("AUR verification failed"))' "$test_tmp/output" >/dev/null
pass "partial AUR coverage shows a lower-bound count, not zero AUR upgrades"

jq -cn '{status:"available",count:100,complete:true,aur:0,counts:{monarch:0,repo:100,aur:0},packages:
  [range(100)|{name:("pkg"+tostring),category:"repo",installed:"1",available:"2"}]}' > "$test_tmp/states"
run_stream
jq -e '(.tooltip | contains("Additional packages: 88")) and
  ([.tooltip | split("\n")[] | select(contains(" → "))]|length) == 12' "$test_tmp/output" >/dev/null
pass "large update lists are capped to twelve package lines"

# Failure retains only explicitly stale information, never an old success label.
cat "$test_tmp/mixed" > "$test_tmp/states"
printf '%s\n' '{"status":"error"}' '{"status":"error"}' '{"status":"current","count":0,"complete":true}' >> "$test_tmp/states"
printf '0\n2\n2\n1\n' > "$test_tmp/codes"
run_stream
jq -se 'length == 3 and .[1].text == "" and .[1].textColor == "on_surface_variant" and
  (.[1].tooltip | contains("Last known updates")) and .[2] == {}' "$test_tmp/output" >/dev/null
[[ $(< "$test_tmp/sleeps") == $'600\n600\n600\n21600' ]] || fail "retry intervals changed"
pass "repeated failures do not accumulate warnings and only complete success clears the badge"

printf '%s\n' 'invalid JSON' '{"status":"available","count":0}' '{"status":"current","count":0,"complete":false}' '{"status":"current","count":0}' > "$test_tmp/states"
printf '0\n0\n1\n1\n' > "$test_tmp/codes"
run_stream
jq -se 'length == 1 and .[0].text == "" and .[0].textColor == "on_surface_variant"' "$test_tmp/output" >/dev/null
pass "invalid or incomplete results are never presented as up to date"

for expression in '.count=99' '.counts.repo="bad"' '.packages[0].available=null' '.complete=null'; do
  jq -c "$expression" "$test_tmp/mixed" > "$test_tmp/states"
  echo 0 > "$test_tmp/codes"
  run_stream
  jq -e '.text == "" and .textColor == "on_surface_variant"' "$test_tmp/output" >/dev/null
done
pass "inconsistent counts and malformed package records cannot produce a trusted badge"

cp "$test_tmp/mixed" "$test_tmp/states"
echo 0 > "$test_tmp/codes"
MONARCH_LANGUAGE=fr run_stream
jq -e '(.tooltip | contains("Mises à jour disponibles")) and (.tooltip | contains("Dépôts"))' "$test_tmp/output" >/dev/null
pass "tooltips follow Monarch interface language"

lua - "$ROOT/default/noctalia/plugins/monarch-indicators/monarch-update.luau" <<'LUA'
local streamed, launched
local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local root = "/path with spaces/Monarch's runtime"
local driver = {
  stream = function(name) streamed = name end,
  bin = function(name) return root .. "/bin/" .. name end,
}
local env = setmetatable({
  require = function(name) assert(name == "./indicator.luau"); return driver end,
  noctalia = { runAsync = function(command) launched = command end },
}, {__index = _G})
assert(loadfile(arg[1], "t", env))()
assert(streamed == "monarch-update.sh")
env.onClick()
assert(launched == quote(driver.bin("monarch-launch-floating-terminal-with-presentation"))
  .. " --app-id=org.monarch.update " .. quote(quote(driver.bin("monarch-update"))))
LUA
pass "widget starts the stream and quotes both terminal-launch command layers"
