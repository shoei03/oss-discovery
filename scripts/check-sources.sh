#!/usr/bin/env bash
# Re-check every endpoint this repository claims works.
#
# The registry tables in docs/ and in the skill are measurements, and measurements go stale.
# PulseMCP started returning 410 without anyone noticing because there was no way to re-run them.
# Run this before editing those tables, and update the tables from this output - not the other way round.
#
# Usage: scripts/check-sources.sh [-v]
# Exits non-zero if any endpoint's status differs from the one recorded here.

set -uo pipefail
VERBOSE=${1:-}
TIMEOUT=25
fail=0

check() { # check <expected> <label> <url> [curl args...]
  local expect=$1 label=$2 url=$3; shift 3
  local got
  got=$(curl -s -o /dev/null -w '%{http_code}' -m "$TIMEOUT" "$@" "$url" 2>/dev/null)
  if [ "$got" = "$expect" ]; then
    [ -n "$VERBOSE" ] && printf '  ok   %-38s %s\n' "$label" "$got"
    return 0
  fi
  printf '  FAIL %-38s expected %s, got %s\n    %s\n' "$label" "$expect" "$got" "$url"
  fail=$((fail + 1))
}

section() { printf '\n%s\n' "$1"; }

section "Cross-ecosystem"
check 200 "deps.dev project"       "https://api.deps.dev/v3/projects/github.com%2FBurntSushi%2Fripgrep"
check 200 "deps.dev dependents"    "https://api.deps.dev/v3alpha/systems/npm/packages/react/versions/18.2.0:dependents"
check 200 "summary.ecosyste.ms"    "https://summary.ecosyste.ms/api/v1/projects/lookup?url=https://github.com/BurntSushi/ripgrep"
check 200 "commits.ecosyste.ms"    "https://commits.ecosyste.ms/api/v1/hosts/GitHub/repositories/vitest-dev%2Fvitest"
check 200 "issues.ecosyste.ms"     "https://issues.ecosyste.ms/api/v1/hosts/GitHub/repositories/vitest-dev%2Fvitest"
check 200 "packages.ecosyste.ms"   "https://packages.ecosyste.ms/api/v1/registries/npmjs.org/packages/vitest"
check 200 "ecosyste.ms registries" "https://packages.ecosyste.ms/api/v1/registries"
check 200 "OSV.dev query"          "https://api.osv.dev/v1/query" -X POST -d '{"package":{"name":"lodash","ecosystem":"npm"},"version":"4.17.11"}'
check 200 "OpenSSF Scorecard"      "https://api.scorecard.dev/projects/github.com/BurntSushi/ripgrep"

section "MCP registries"
check 200 "official MCP /v0.1"     "https://registry.modelcontextprotocol.io/v0.1/servers?limit=1"
check 200 "official MCP openapi"   "https://registry.modelcontextprotocol.io/openapi.yaml"
check 200 "Smithery"               "https://registry.smithery.ai/servers?pageSize=1"
check 200 "GitHub MCP Registry"    "https://api.mcp.github.com/v0/servers?limit=1"
check 200 "Docker MCP Catalog"     "https://hub.docker.com/v2/repositories/mcp/?page_size=1"
# Recorded as broken on purpose. If these ever stop failing, the tables need updating too.
check 410 "PulseMCP v0beta (dead)" "https://api.pulsemcp.com/v0beta/servers"
check 401 "PulseMCP v0.1 (keyed)"  "https://api.pulsemcp.com/v0.1/servers"
check 401 "Glama (keyed)"          "https://glama.ai/api/mcp/v1/servers"

section "Domain registries"
check 200 "Artifact Hub"           "https://artifacthub.io/api/v1/packages/search?ts_query_web=prometheus&limit=1"
check 200 "CNCF Landscape"         "https://landscape.cncf.io/data/full.json"
check 200 "Homebrew analytics"     "https://formulae.brew.sh/api/analytics/install/365d.json"
check 200 "Arch AUR"               "https://aur.archlinux.org/rpc/v5/info?arg[]=yay"
check 200 "Debian popcon"          "https://popcon.debian.org/by_inst"
check 200 "Hugging Face Hub"       "https://huggingface.co/api/models?search=qwen&limit=1"
check 200 "Terraform Registry"     "https://registry.terraform.io/v2/providers/323"
check 200 "Ansible Galaxy"         "https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/?limit=1"
check 200 "Open VSX"               "https://open-vsx.org/api/-/search?query=python&size=1"
check 200 "JetBrains Marketplace"  "https://plugins.jetbrains.com/api/searchPlugins?search=rust&max=1"
check 200 "Docker Hub search"      "https://hub.docker.com/v2/search/repositories?query=nginx&page_size=1"
check 200 "awesome.ecosyste.ms"    "https://awesome.ecosyste.ms/api/v1/lists?per_page=1"
# Documented gotcha: crates.io refuses a request with no User-Agent.
check 403 "crates.io (no UA)"      "https://crates.io/api/v1/crates?q=serde"
check 200 "crates.io (with UA)"    "https://crates.io/api/v1/crates?q=serde" -A "oss-discovery/check-sources"

if [ "$fail" -eq 0 ]; then
  printf '\nAll endpoints match what the tables record.\n'
else
  printf '\n%d endpoint(s) drifted. Re-measure, then update the tables and this script together.\n' "$fail"
fi
exit $((fail > 0))
