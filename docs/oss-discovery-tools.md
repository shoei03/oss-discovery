# Tools and harnesses for finding OSS

Measured: 2026-09-19 / Environment: macOS (darwin 25.6.0), `gh` 2.97.0 (authenticated)
Purpose: compare the ways to find OSS on GitHub and judge whether to adopt it, for **technical investigation and adoption decisions**.

Every command and API here was actually executed and verified. Things that did not work are recorded too, with the reason.
For an overview of the project and how to install the skill, see the [README](../README.md).

> Endpoints go stale. `scripts/check-sources.sh` re-runs every one of them and reports what drifted.
> Run it before editing any table here, and update the tables from its output - not the other way round.

> Trend tracking (which repositories are growing right now) is out of scope for this document.
> The state of the event data and the alternatives are covered in [github-trend-data.md](./github-trend-data.md).

---

## Contents

1. [Conclusion (quick reference)](#1-conclusion-quick-reference)
2. [Premise: you cannot search in natural language](#2-premise-you-cannot-search-in-natural-language)
3. [The workflow: find, narrow, evaluate, read](#3-the-workflow-find-narrow-evaluate-read)
4. [Tool comparison](#4-tool-comparison)
5. [Recipe](#5-recipe)
6. [Appendix: considered and rejected](#6-appendix-considered-and-rejected)
7. [Sources](#7-sources)

---

## 1. Conclusion (quick reference)

| What you want | What to use | Stage |
|---|---|---|
| The target belongs to a specific domain (MCP, plugins, ...) | **Run the workflow twice.** Pass 1 outputs a domain registry; pass 2 uses it | 1-4, twice |
| Turn a vague request into candidates | **Have the agent (Claude Code) translate it** | 1. Find |
| You don't know any names at all | **Exa** (neural search) to surface names | 1. Find |
| List the leading repositories in a field | **`gh search repos`**, the union of a topic, a phrase and a `topics:0` query | 2. Narrow |
| Reach the organizations topic search drops | **Owner frequency, then `--owner=`** (snowball) | 2. Narrow |
| Keep only repositories that are still alive | **GraphQL** (recent commit counts in one request) | 2. Narrow |
| Score one candidate in a single call | **summary.ecosyste.ms** `projects/lookup` (`dds`, packages, files) | 3. Evaluate |
| Decide whether to adopt | **ecosyste.ms packages API** (dependent-count percentile) | 3. Evaluate |
| Check security health | **deps.dev** (Scorecard embedded), **OSV.dev** for the pinned version | 3. Evaluate |
| Understand a repository's design and implementation | **DeepWiki MCP** | 4. Read |
| Check how to use a current API | **Context7 MCP** | 4. Read |

**The two lowest-cost additions** (neither needs an API key, both work immediately):

```bash
claude mcp add -s user -t http deepwiki https://mcp.deepwiki.com/mcp
claude plugin install exa@claude-plugins-official
```

---

## 2. Premise: you cannot search in natural language

### Experiment: what happens when you send a raw sentence

```bash
gh search repos "a tool that autocompletes SQL when you write in terminal"  # 0 results
gh search repos "autocomplete SQL terminal" --match=readme                  # 0 results
```

GitHub search is an **AND search over keywords**. Feed it a sentence and it goes looking for repositories
containing every word in it, and returns nothing. Widening to README bodies changes nothing.

Translate the intent into qualifiers and it lands:

```bash
gh search repos --topic=sql --topic=cli --stars=">500" --archived=false --sort=stars
# 6404  tconbeer/harlequin   The SQL IDE for Your Terminal.   <- exactly what was wanted
# 10362 harelba/q            Run SQL directly on delimited files...
# 5269  cube2222/octosql     query tool that allows you to join, analyse...
```

### GitHub's own semantic search does not reach this

Natural-language search arrived in February 2026, but it is **issues only, and web UI only**.

- Repository search and code search are not covered
- Without a repository scope it is limited to **your top 100 repositories**
- Quoted exact matches and filter-only searches fall back to lexical search
- **It is not available through the REST API.** Sending a natural-language sentence to `search/issues`
  with `advanced_search=true` returned 0 results, the same as without it

### No dedicated harness exists for natural-language-to-query

I looked. Nothing mature turned up.

| Candidate | Reality |
|---|---|
| **OSS Insight Data Explorer** | Exactly this (natural language to SQL, built on Chat2Query), but `ossinsight.io/explore` is currently **"under maintenance"** |
| **`gh copilot suggest`** | Natural language to command. **Deprecated 2025-10-25**, repository archived, folded into the agentic Copilot CLI |
| **Official GitHub plugin** | `external_plugins/github` contains only `.mcp.json` (an MCP connection config). No search skill. `github-mcp-server` itself has no skills directory either |
| **Semantic-search MCP servers** (`github-semantic-search-mcp`, `semcode`, `osgrep`, and others) | All of them search **inside repositories you have already indexed**. Not for finding which one to use |

**GitHub's own judgement is the notable part.** It deprecated `gh copilot suggest`, a dedicated translator,
and folded it into an agentic CLI. The industry has already rejected the idea of a dedicated
natural-language-to-query harness.

**Consequence: the translation layer is the agent (Claude Code).** Writing your own natural-language parser
or query builder reinvents the wheel.

---

## 3. The workflow: find, narrow, evaluate, read

```
a vague request
    |
    +-- 1. Find      check for a domain registry, then agent translates vocabulary / Exa
    +-- 2. Narrow    gh search repos, then GraphQL to confirm it is alive
    +-- 3. Evaluate  ecosyste.ms (real usage), then Scorecard (health)
    +-- 4. Read      DeepWiki MCP, then Context7 MCP
    |
an adoption decision
```

### 3.1 Find - registry first, vocabulary second

#### A domain registry, when one exists, is the output of pass 1

When the target belongs to a specific domain (MCP servers, plugins, packages in a particular ecosystem),
**finding the registry is not a shortcut within stage 1; it is what you get from one full pass of the workflow.**

```
Pass 1: target = "the means of searching this domain"
    1. Find      list registry candidates with gh search repos
    2. Narrow    keep the live ones, the official ones
    3. Evaluate  decide whether this registry can be trusted
    4. Read      clarify the API, its query parameters, its constraints
                 The output is the search mechanism itself.

Pass 2: target = what you actually wanted
    1. Find      search through the registry's API, in place of GitHub search
    2-4.         as usual
```

**Do not skip stage 4.** What a registry can do is unknowable until you read the spec, and inference gets it
wrong (worked example below).

#### Pass 1 in practice (looking for MCP servers)

```bash
# 1. Find
gh search repos --topic=mcp --topic=registry --stars=">100" --archived=false --sort=stars
# 2360  Observal/Observal                      self-hosted registry for coding agent extensions
# 933   agentic-community/mcp-gateway-registry Enterprise-ready MCP Gateway & Registry

# 2. Narrow - check the provenance of the official implementation
gh repo view modelcontextprotocol/registry \
  --json nameWithOwner,stargazerCount,pushedAt,description
# 7265 stars  push:2026-09-16  A community driven registry service for MCP servers
```

**4. Read - clarify the API.** In this order of preference:

1. **An OpenAPI spec, if one exists, comes first** (machine-readable, exhaustive, no inference)
2. To understand the repository's design, ask **DeepWiki MCP** about `modelcontextprotocol/registry`
3. If you will use a client library, check version-specific APIs through **Context7 MCP**

```bash
curl -s "https://registry.modelcontextprotocol.io/openapi.yaml" -o reg.yaml   # HTTP 200
grep -E '^  /' reg.yaml            # endpoint list
# /v0/servers, /v0/servers/{serverName}/versions, /v0/publish, /v0/health, ...
# /v0.1/... also exists (a newer API version, responds 200)
```

Query parameters for `/v0/servers`, as established from the spec:

| Parameter | Meaning |
|---|---|
| `search` | **Substring match on the server name only** (descriptions are not searched) |
| `updated_since` | Updated at or after an RFC3339 timestamp |
| `version` | `latest`, or an exact version such as `1.2.3` |
| `limit` / `cursor` | Page size and cursor pagination |
| `include_deleted` | Include deleted servers (always true when `updated_since` is given) |

#### Pass 2: search for what you actually wanted

```bash
# By name
curl -s "https://registry.modelcontextprotocol.io/v0/servers?search=github&limit=5" \
  | jq -r '.servers[] | "\(.server.name)\t\(.server.description[0:55])"'

# Only what was updated this month
curl -s "https://registry.modelcontextprotocol.io/v0/servers?updated_since=2026-09-01T00:00:00Z&limit=3" \
  | jq -r '.servers[] | "\(.server.name)\t\(._meta."io.modelcontextprotocol.registry/official".updatedAt[0:10])"'

# By transport type - not an API parameter, so filter client-side
curl -s "https://registry.modelcontextprotocol.io/v0/servers?limit=100" \
  | jq -r '.servers[] | select(.server.remotes[]?.type == "streamable-http") | .server.name'
```

> **A worked example of misjudging capability by skipping stage 4.** The first version of this report claimed
> you could filter for "only the ones that run over Streamable HTTP". Reading the OpenAPI spec shows there is
> no transport-type query parameter; you have to fetch and then filter on `remotes[].type`. Likewise `search`
> covers names only and never looks at descriptions, so a word that appears only in a description
> (`fastest`, for instance) returns 0 results - measured.

#### Package ecosystems do not need a list at all

Writing "npm, PyPI, crates.io, ..." into a document is a maintenance liability, and unnecessary: the set
is queryable.

```bash
curl -s "https://packages.ecosyste.ms/api/v1/registries" \
  | jq -r '.[] | "\(.name)\t\(.ecosystem)\t\(.packages_count)"' | sort -t$'\t' -k3 -rn | head
# npmjs.org        npm       5875202
# proxy.golang.org go        2359001
# hub.docker.com   docker    1002713
# pypi.org         pypi       936154
# nuget.org        nuget      854022
# repo1.maven.org  maven      624857
# ... 100 registries in total
```

Select by `ecosystem`, then resolve at `/api/v1/registries/<name>/packages/<pkg>`.

#### The same shape elsewhere

Measured 2026-09-19. Status codes are from `scripts/check-sources.sh`, which re-runs all of them.

| Target | Registry | Status |
|---|---|---|
| MCP servers | `registry.modelcontextprotocol.io/v0.1/servers` (official, publishes OpenAPI; `/v0` still answers) | 200, keyless |
| | `registry.smithery.ai/servers` - 15,579 servers, carries `useCount` and `verified` | 200, keyless |
| | `api.mcp.github.com/v0/servers` - 252, curated, embeds `repository.readme` | 200, keyless |
| | `hub.docker.com/v2/repositories/mcp/` - 245 images with `pull_count` | 200, keyless |
| | ~~Glama~~ `glama.ai/api/mcp/v1/servers` | **401**, key required |
| | ~~PulseMCP~~ `api.pulsemcp.com/v0beta/servers` | **410**, sunset |
| Claude Code plugins and skills | `.claude-plugin/marketplace.json` in `anthropics/claude-plugins-official`, and `anthropics/skills` | - |
| Any package | the registry listing above, then ecosyste.ms (see section 3.3) | 200, keyless |
| Everything else | [the skill's registry reference](../plugins/oss-discovery/skills/oss-discovery/references/registries.md) - Kubernetes/Helm, CLI install counts, ML models, IaC, editor extensions, containers, vulnerabilities | - |

**Read `marketplace.json`, not the directory listing.** It holds **310 entries** (161 `url`,
97 `git-subdir`, 38 `./plugins/`, 14 `./external_plugins/`) against 39 + 14 directories on disk.
Counting directories understates the marketplace by a factor of six. `anthropics/skills` (177,072 stars)
additionally ships `spec/` and `template/` next to its 19 skills.

#### Topic search misses roughly a third of the field

GitHub Topics is opt-in and the largest repositories frequently skip it. Measured by comparing
`total_count` for `topics:0` against the same star range:

| Range | No topics | Total | Missing |
|---|---|---|---|
| `stars:>500` | 47,739 | 123,029 | **38.8%** |
| `stars:>1000` | 22,259 | 64,904 | 34.3% |
| `stars:>5000` | 3,060 | 12,572 | 24.3% |
| `stars:>10000` | 1,113 | 5,565 | 20.0% |
| `stars:>50000` | 72 | 492 | 14.6% |

`--stars=">500"` is exactly what section 3.1 recommends, so the recommended query is structurally blind to
38.8% of the field. Repositories carrying no topics at all include `anthropics/claude-code` (146,435),
`openai/codex` (125,214), `modelcontextprotocol/servers` (90,455), `cline/cline` (68,723),
`torvalds/linux` and `python/cpython` - that is, this skill's own subject matter is over-represented among
the misses. The subtler failure is a repository with topics that are not the ones you would guess:
`jqlang/jq` is tagged `[jq]` and nothing else, `ggml-org/llama.cpp` is `[ggml]` alone.

**Demonstration.** `gh search repos --topic=mcp --stars=">500" --limit=100` returns 100 repositories and
**`modelcontextprotocol/servers` is not among them** - the reference server collection for the entire
protocol. `gh search repos "model context protocol" --match=name,description --stars=">500"` returns it
first. The counts are comparable (`topic:mcp stars:>500` = 994, `mcp in:name,description stars:>500` = 867)
but the sets differ, so the union is what matters.

```bash
gh search repos --topic=<t> --stars=">500" --archived=false --limit=100 --json fullName   # 100 hits
gh search repos "<phrase>" --match=name,description --stars=">500" --limit=100 --json fullName
gh search repos "<kw>" --match=name,description --number-topics=0 --stars=">1000" --limit=50 --json fullName
# union of the three, deduplicated: 236 unique repositories
```

The third query (`--number-topics=0`, i.e. the `topics:0` qualifier) exists to fetch precisely the set that
topic search cannot reach.

> **A registry is never a reason to skip evaluation.** Listings are largely self-reported, so
> **absence does not mean it does not exist**, and **presence does not mean it is any good**
> (the official MCP registry carries paid data feeds advertising `$0.01/query`).
> Once pass 2 has produced candidates, return to the criteria in section 3.3. GitHub search and registries are
> complements, not replacements.

#### Translating into vocabulary

When no dedicated registry exists (and alongside one when it does), hand the request to the agent as-is and
have it translated. The shape of the translation:

| Element of the request | Translates to |
|---|---|
| The function in "a tool that does X" | Several `--topic=` values (GitHub Topics is a normalized vocabulary) |
| "in the terminal", "as a CLI" | `--topic=cli`, `--topic=terminal` |
| A stated or inferred language | `--language=` |
| "something solid", "the standard one" | `--stars=">500"` plus `--archived=false` |
| "something still usable" | `--updated=">2026-06-01"` |
| "something recent" | `--created=">2026-01-01"` |

Split the vocabulary candidates across several queries and merge the results. Do not try to land it in one query.

**Exa (supporting role)** is the way in when no names are known at all. Being a neural search, it accepts
vague questions.

```bash
claude plugin install exa@claude-plugins-official   # in the official marketplace
```

- Official MCP: `https://mcp.exa.ai/mcp`, **usable free without a key** (rate limited)
- Tools: `web_search_exa`, `web_fetch_exa`, `web_search_advanced_exa` (opt-in)
- Note that `category` has no `github` value; it narrows a general web search by domain. In practice you pick
  names out of blog posts and comparisons, then confirm them on GitHub

### 3.2 Narrow - `gh search repos` and GraphQL

The workhorse (verified):

```bash
gh search repos --language=rust --topic=cli \
  --stars=">2000" --updated=">2026-06-01" --archived=false \
  --sort=stars --limit=20 \
  --json fullName,stargazersCount,pushedAt,description
```

Key flags: `--language` `--topic` `--stars` `--created` `--updated` `--archived` `--license`
`--include-forks` `--match {name|description|readme}` `--number-topics` `--owner`
`--sort {stars|forks|updated|help-wanted-issues}`

#### Snowball the organizations out of the results

Section 3.1 shows that topic search drops well-known organizations. The fix is not a list of organizations
- a list goes stale, and `anthropics/anthropic-quickstarts` has already been renamed to
`claude-quickstarts`. Derive the organizations from the search you just ran.

```bash
# 1. Owner frequency in the first pass
gh search repos "model context protocol" --match=name,description --stars=">500" --limit=50 --json fullName \
  | jq -r '.[].fullName' | cut -d/ -f1 | sort | uniq -c | sort -rn | head -5
#   14 modelcontextprotocol
#    3 mark3labs
#    2 zcaceres
#    2 microsoft

# 2. Search the dominant owner directly
gh search repos --owner=modelcontextprotocol --stars=">100" --limit=30 --json fullName,stargazersCount
#   90455 servers        24340 python-sdk    13428 typescript-sdk
#   10913 inspector       9254 modelcontextprotocol   7264 registry
#    5121 go-sdk          4535 csharp-sdk     3940 rust-sdk    3701 java-sdk
```

Measured: step 2 returned 25 repositories, **10 of which none of the three section-3.1 queries had found**,
including `inspector` (10,913 stars), `conformance`, `ext-auth` and `use-mcp`. The owner comes from the
data, so the same two steps work in any domain.

When no name at all is known, ask GitHub for the organizations rather than writing them down:

```bash
gh api -X GET search/users -f q='type:org followers:>30000' -f sort=followers -f order=desc \
  -f per_page=30 --jq '.items[].login'
# openai microsoft deepseek-ai anthropics github google huggingface TheAlgorithms EpicGames
# modelcontextprotocol apple facebookresearch facebook freeCodeCamp python vercel NVIDIA ...
# (total_count 22 at this threshold; lower it for a wider list)
```

Note that `gh search users` does not exist in gh 2.97.0 - `gh search` covers code, commits, issues, prs and
repos only. The user search has to go through `gh api`.

#### gh CLI traps (all measured)

| Trap | Detail |
|---|---|
| Multiple `org:` qualifiers | Must be **separate shell arguments**. `gh search repos "org:a org:b kw"` fails with `Invalid search query "org:\"a org:b kw\""`. `gh search repos kw org:a org:b` works, as does `--owner=a,b` |
| `in:topics` | Has no `gh` flag. `--match` accepts `name|description|readme` only; write the raw qualifier |
| `--number-topics=N` | This is the `topics:N` qualifier. `--number-topics=0` isolates untagged repositories |
| Negation | Goes after `--`: `gh search repos --topic=mcp -- -topic:awesome` |
| Totals | `gh search repos` cannot report one. Use `gh api -X GET search/repositories -f q='...' --jq .total_count` |
| 1,000 ceiling | `gh api search/repositories -f q='stars:>1000' -f per_page=100 -f page=11` returns **HTTP 422**, "Only the first 1000 search results are available" |

> **Always pass `--archived=false`.** Without it, repositories that stopped years ago dominate the top.
> Pair it with `--updated=">..."` to drop dead projects.

**Search API limits** (these always bite at design time):

| Limit | Value |
|---|---|
| Maximum results per query | **1,000** (paging cannot exceed it) |
| Per page | 100 |
| Rate limit (authenticated) | **30 req/min** (10 req/min for code search) |
| Rate limit (unauthenticated) | 10 req/min |
| Query length | 256 characters (excluding operators and qualifiers) |
| Boolean operators | at most five `AND` / `OR` / `NOT` combined |
| On timeout | returns partial results with `incomplete_results: true` |

```bash
gh api /rate_limit --jq '{core:.resources.core, search:.resources.search, graphql:.resources.graphql}'
# search is 30/min; core and graphql are 5000/hour (separate budgets)
```

Work around the 1,000 ceiling by **splitting the query** (`stars:1000..2000`, `stars:2000..5000`,
`stars:>5000`, and so on).

**Confirm it is alive, with GraphQL.** Recent commit counts, which the Search API cannot return, in a single
request. This draws on the 5,000 pt/hour budget, separate from core.

```bash
gh api graphql -f query='
{
  search(query: "topic:mcp stars:>500 pushed:>2026-06-01", type: REPOSITORY, first: 20) {
    repositoryCount
    nodes { ... on Repository {
      nameWithOwner stargazerCount pushedAt
      licenseInfo { spdxId }
      defaultBranchRef { target { ... on Commit {
        history(since: "2026-06-01T00:00:00Z") { totalCount }
      }}}
    }}
  }
}'
```

In the run above this returned `repositoryCount: 854` along with each repository's commit count since June.
**Being able to mechanically drop "lots of stars, development stopped" is the biggest win here.**

### 3.3 Evaluate - ecosyste.ms and Scorecard

The **ecosyste.ms packages API** is the centrepiece of an adoption decision. Free, no authentication,
open data (code AGPL-3, data CC BY-SA 4.0).

```bash
curl -s "https://packages.ecosyste.ms/api/v1/registries/npmjs.org/packages/vitest" \
  | jq '{name, latest_release_number, dependent_packages_count, dependent_repos_count, downloads, rankings}'
```

Measured, for vitest:

```json
{
  "dependent_packages_count": 11085,
  "dependent_repos_count": 30558,
  "downloads": 374745724,
  "rankings": { "downloads": 0.095, "dependent_repos_count": 0.176, "average": 0.471 }
}
```

(`downloads` is the last-month figure.) `rankings` gives the **percentile across all packages (lower is
better)**: top 0.1% by downloads, top 0.18% by dependent repositories. **Unlike star count it reflects
whether something is actually used, which makes it more trustworthy than stars for an adoption decision.**

Repository-side metadata is available too:

```bash
curl -s "https://repos.ecosyste.ms/api/v1/hosts/GitHub/repositories/BurntSushi/ripgrep"
curl -s "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/sxyazi/yazi"
```

#### One call per candidate: summary.ecosyste.ms

```bash
curl -s "https://summary.ecosyste.ms/api/v1/projects/lookup?url=https://github.com/BurntSushi/ripgrep" \
  | jq '{stars:.repository.stargazers_count, archived:.repository.archived,
         license:.repository.license, dds:.commits.dds,
         committers:.commits.total_committers, past_year:.commits.past_year_total_commits,
         packages:(.packages|length), security_md:(.repository.metadata.files.security != null)}'
```

Measured, for ripgrep: `dds 0.320`, `total_committers 481`, `total_commits 2225`,
`past_year_total_commits 227`, 100 packages, no SECURITY.md. For vitest: `dds 0.678`, 805 committers.

**`commits.dds` is the Development Distribution Score - the bus factor.** A low value means one person
writes nearly everything. Neither GitHub search nor the GitHub API exposes this, and it is a first-order
adoption risk. `commits.ecosyste.ms/api/v1/hosts/GitHub/repositories/<owner>%2F<repo>` returns the same
field on its own, along with the bot-commit split.

Two fields are not what they look like, and both were established by reading the actual response rather
than the field names:

- **`score` is ecosyste.ms's own project score, not OpenSSF Scorecard.** ripgrep scores 37.3 here and
  4.7 on Scorecard. Reading it on Scorecard's 0-10 scale is a serious misreading
- **`.issues` comes back as a bare `{table: {...}}` stub** with `avg_time_to_close_pull_request` and its
  neighbours all `null`, for ripgrep and vitest alike. Issue statistics need their own call:

```bash
curl -s "https://issues.ecosyste.ms/api/v1/hosts/GitHub/repositories/vitest-dev%2Fvitest" \
  | jq '{avg_time_to_close_issue, avg_time_to_close_pull_request, issue_authors_count}'
# 6151727.5 s (71 days) to close an issue, 1160654.9 s (13.4 days) to close a PR, 2573 issue authors
```

Note the path shapes differ between services: `repos.` wants a raw slash
(`hosts/GitHub/repositories/OWNER/REPO`, `%2F` gives 404), while `commits.` and `issues.` want `%2F`.

#### Security: deps.dev carries Scorecard, but does not widen its coverage

```bash
curl -s "https://api.deps.dev/v3/projects/github.com%2FBurntSushi%2Fripgrep" \
  | jq '{starsCount, license, date:.scorecard.date, score:.scorecard.overallScore,
         checks:[.scorecard.checks[]?|{name,score}]}'
# 68215 stars, "non-standard", 2026-08-24, 4.7
# Maintained 10 / Code-Review 2 / Dangerous-Workflow 10 / Binary-Artifacts 10 / Token-Permissions 0
```

```bash
curl -s "https://api.scorecard.dev/projects/github.com/BurntSushi/ripgrep" | jq '{score, date}'
# 4.7, 2026-09-14
```

**The two agree, and they are missing the same repositories.** Measured across four repositories:

| Repository | api.scorecard.dev | deps.dev `.scorecard` |
|---|---|---|
| `BurntSushi/ripgrep` | 200, score 4.7 | 4.7 |
| `tconbeer/harlequin` | **404** | absent |
| `sxyazi/yazi` | **404** | absent |
| `zcaceres/mcp-sequentialthinking-tools` | **404** | absent |

So deps.dev is preferable as the default call - it returns 200 with stars, license and deprecation data
even when no Scorecard exists, instead of failing the request - but it is **not** a way to get Scorecard
data for unscanned projects. When a Scorecard does exist, `api.scorecard.dev` is the fresher of the two
(2026-09-14 against 2026-08-24).

Measured: ripgrep scores **4.7 out of 10** overall (`Code-Review: 2`, "Found 6/23 approved changesets").

> **How to read it:** ripgrep is an extremely widely used, high-quality project, but its single-maintainer
> model loses points on review-related checks. **Do not cut on the aggregate score**; read the individual
> checks (`Vulnerabilities`, `Dangerous-Workflow`, `Maintained`, `Signed-Releases`).

#### deps.dev dependents are per version, not per package

```bash
curl -s "https://api.deps.dev/v3alpha/systems/npm/packages/react/versions/18.2.0:dependents"
# {"dependentCount":13438,"directDependentCount":5213,"indirectDependentCount":8471}
curl -s "https://api.deps.dev/v3alpha/systems/npm/packages/vitest/versions/5.0.1:dependents"
# {"dependentCount":91,"directDependentCount":60,"indirectDependentCount":32}
```

vitest 5.0.1 is the current release of a package with `dependent_packages_count: 11085` on ecosyste.ms.
The 91 is not a contradiction: **`:dependents` answers "has this release been picked up yet", while
ecosyste.ms answers "is this package widely used".** Using the former as a popularity signal will make
every recent release look abandoned. Note also that `:dependents` lives on `v3alpha` only; `v3` has no
equivalent.

#### Known vulnerabilities: OSV.dev

```bash
curl -s -X POST https://api.osv.dev/v1/query \
  -d '{"package":{"name":"lodash","ecosystem":"npm"},"version":"4.17.11"}' | jq '[.vulns[].id]'
# 7 advisories, starting GHSA-29mw-wpgm-hmr9
```

Keyless, OpenAPI published, and `/v1/querybatch` judges a whole shortlist in one request. This is the
check that belongs against the version you would actually pin, which Scorecard's `Vulnerabilities` check
does not cover at that granularity.

**Order of judgement:**

1. **Is it maintained?** Commits in the last three months above zero, `archived: false`
2. **Is it actually used?** The `dependent_repos_count` percentile
3. **Is one person carrying it?** `commits.dds`
4. **License.** `licenseInfo.spdxId`. `NOASSERTION` needs a closer look
5. **Security.** The individual Scorecard checks, plus OSV for the version you would pin
6. Star count. **Look at this last.** Marketing moves it easily

### 3.4 Read - MCP

**DeepWiki MCP** (from Cognition). Parses a public repository into a wiki you can question in natural language.

```bash
claude mcp add -s user -t http deepwiki https://mcp.deepwiki.com/mcp
```

- Endpoint `https://mcp.deepwiki.com/mcp` (Streamable HTTP), **no authentication, free** (public repos only)
- Tools: `read_wiki_structure`, `read_wiki_contents`, `ask_question`
- Use it to ask "where are the extension points in this library?" or "how is the auth flow implemented?"
  without cloning
- **Not usable for discovery.** It assumes you already know the repository name

**Context7 MCP** is for the implementation phase after adoption is decided. It pulls accurate
version-specific API references.

- Endpoint `https://mcp.context7.com/mcp`, **API key required** (free from context7.com/dashboard)
- Tools include `resolve-library-id`
- Available as `external_plugins/context7` in the official marketplace

**Official GitHub MCP Server** is **low priority if all you want is search.** The `gh` CLI covers it, and the
tool definitions consume context. Adopt it when you also want issue creation and PR review handled.

```bash
claude plugin install github@claude-plugins-official    # official plugin (only an MCP connection config)
# or directly:
claude mcp add github -e GITHUB_PERSONAL_ACCESS_TOKEN=<token> -- \
  docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN ghcr.io/github/github-mcp-server
```

- Remote: `https://api.githubcopilot.com/mcp/` (OAuth, token held in memory only)
- Toolsets: `repos`, `issues`, `pull_requests`, `actions`, `code_security`, and others
- For discovery, `GITHUB_TOOLSETS=repos` plus `--read-only` is the safe configuration

---

## 4. Tool comparison

Automatable: "full" means scriptable without a browser; "partial" means possible but awkward;
"no" means there is no API.

| Tool | Kind | Auth | Automatable | State | Primary use |
|---|---|---|---|---|---|
| `gh search repos` | CLI | yes (gh auth) | full | working | 2. Narrow (workhorse) |
| GitHub GraphQL | API | yes | full | working | 2. Narrow (liveness) |
| Domain registries (e.g. official MCP registry) | API | **no** | full | working | 1. Find (first choice where one exists) |
| GitHub Topics / Explore | Web | no | partial | working | 1. Find |
| Exa | MCP/API | **no** (keyless) | partial | working | 1. Find (vague entry point) |
| ecosyste.ms packages | API | **no** | full | working (weak search) | 3. Evaluate (centrepiece) |
| ecosyste.ms summary | API | **no** | full | working | 3. Evaluate (one call per candidate, `dds`) |
| ecosyste.ms issues | API | **no** | full | working | 3. Evaluate (close times; not in summary) |
| deps.dev | API | **no** | full | working | 3. Evaluate (Scorecard, license, deprecation) |
| OpenSSF Scorecard | API | **no** | full | working (404 if unscanned) | 3. Evaluate (freshest score) |
| OSV.dev | API | **no** | full | working | 3. Evaluate (vulnerabilities per version) |
| Artifact Hub | API | **no** | full | working | 1. Find (Kubernetes/Helm, CVE counts in results) |
| Homebrew analytics | API | **no** | full | working | 3. Evaluate (absolute CLI install counts) |
| Hugging Face Hub | API | **no** | full | working | 1. Find (models/datasets, `downloads`) |
| Libraries.io | API | yes (free key, 60 req/min) | partial | **deprecated here** | superseded, see section 6 |
| DeepWiki | MCP | **no** | partial | working | 4. Read |
| Context7 | MCP | yes (free key) | partial | working | 4. Read (implementation) |
| Official GitHub MCP | MCP | yes (PAT/OAuth) | partial | working | when writes are also delegated |

---

## 5. Recipe

One pass from a vague request to a decision. Only stage 1 is handed to the agent; everything from stage 2 on
can be run as written.

**1. Find - what to ask the agent**

Sending natural language straight to search returns nothing (section 2), so a translation step goes first.

```
"Find OSS that fits <vague request>.
 If the domain has a dedicated registry, first pin down the registry itself through stages 1-4
 (using stage 4 to read its OpenAPI or DeepWiki and establish how the API works and what it cannot do),
 then run a second pass using that API as the search mechanism.
 If there is none, translate into topic/language with the table in section 3.1 and merge several queries,
 confirm liveness per section 3.2, and narrow to three candidates using the priorities in section 3.3."
```

When no names are known at all, use Exa or a web search first to pick names out of blog posts and
comparisons, then confirm them on GitHub.

**2-4. Commands to run**

```bash
# 2. Narrow: list only what is alive
gh search repos --language=typescript --topic=orm \
  --stars=">1000" --updated=">2026-06-01" --archived=false \
  --sort=stars --limit=20 --json fullName,stargazersCount,license,pushedAt

# 2. Narrow: verify development activity (do not be fooled by stars)
gh api graphql -f query='{ search(query:"...", type:REPOSITORY, first:20){ nodes{ ... on Repository {
  nameWithOwner stargazerCount
  defaultBranchRef{target{... on Commit{history(since:"2026-06-01T00:00:00Z"){totalCount}}}}
  issues(states:OPEN){totalCount} pullRequests(states:OPEN){totalCount}
}}}}'

# 3. Evaluate: how widely it is actually used (more reliable than stars)
curl -s "https://packages.ecosyste.ms/api/v1/registries/npmjs.org/packages/<pkg>" \
  | jq '{dependent_repos_count, downloads, rankings}'

# 3. Evaluate: security health
curl -s "https://api.scorecard.dev/projects/github.com/<owner>/<repo>" \
  | jq '{score, checks: [.checks[]|{name,score}]}'

# 4. Read: ask DeepWiki MCP "how is <concern> implemented in this repository?"
```

---

## 6. Appendix: considered and rejected

Kept so that nobody repeats the investigation.

| Subject | Why it was rejected |
|---|---|
| **ecosyste.ms search features** | `topics/mcp` returns `repositories_count: 0` (the topic index has not kept up). `repositories?sort=stargazers_count` ignores the sort and returns name order. **Treat it as a lookup tool, not a search tool** |
| **Libraries.io** | **Downgraded 2026-09-19 from "fallback" to "do not reach for it".** `/api/search` returns 401 without a key (60 req/min once you have one), Tidelift has been acquired by Sonar, and the data has rotted - `react` carries `repository_url: github.com/react/react`, which does not exist. deps.dev plus ecosyste.ms cover the same ground keyless |
| **PulseMCP** | `api.pulsemcp.com/v0beta/servers` returns **HTTP 410**: "Starting January 2026: 1% of requests fail ... September 2026: Fully sunset (100%)". The v0.1 replacement needs an `X-API-Key` header. It sat in the registry table as a keyless option and nobody noticed, which is why `scripts/check-sources.sh` now exists |
| **Glama** | `glama.ai/api/mcp/v1/servers` returns **401**. Beyond the key, the API Data License requires visible Glama attribution on every page displaying the data plus a link to the record's listing - a licensing obligation, not just an auth step |
| **GitHub Actions Marketplace** | No listing API exists. `docs.github.com/en/rest/apps/marketplace` covers plans for *your own* listing only, and `github.com/marketplace?type=actions` is HTML. Use `gh search repos --topic=github-action`, or check for `action.yml` via the contents API |
| **OpenSSF Criticality Score / Allstar** | No hosted API. Criticality Score ships as a CLI with periodic CSV/BigQuery dumps; Allstar is a policy-enforcement GitHub App. Neither can be called on demand during a search |
| **Software Heritage** | `archive.softwareheritage.org/api/1/origin/search/` works, but anonymous rate limits are severe and the purpose is archival preservation, not adoption judgement |
| **Maven Central search** | `search.maven.org/solrsearch/select` does not connect at all (HTTP 000). `central.sonatype.com/api/internal/browse/components` answers on POST but is explicitly an internal endpoint |
| **Scoop / winget / dotfyle / mcp.so / Continue hub** | No usable public JSON API. `scoopsearch.search.windows.net` is 403 without a key, `api.winget.run` answers but its data stops at 2023-03-16, dotfyle and mcp.so are SPAs with no API behind them, `hub.continue.dev` does not resolve |
| **Semantic-search MCP servers** (`github-semantic-search-mcp` 31 stars, `semcode`, `semantic-code-mcp`, `osgrep`) | All search inside repositories that were indexed beforehand. Not a discovery tool |
| **Exa's `category=github`** | No such value exists (`company`, `publication`, `news`, and so on). Use domain narrowing instead |
| **OSS Insight Data Explorer** | A dedicated natural-language-to-SQL harness, but `ossinsight.io/explore` is "under maintenance" |
| **`gh copilot suggest`** | Deprecated 2025-10-25, repository archived, folded into Copilot CLI |
| **OpenHub** | Crawls infrequently; its data goes stale |
| **GH Archive / OSS Insight trend API** | Out of scope here, but for trend work their collection is broken. See [github-trend-data.md](./github-trend-data.md) |

### Other health-evaluation tools

- **deps.dev** (Google): promoted into section 3.3 on 2026-09-19. It had been sitting in this appendix
  marked "verified working" while the skill kept calling `api.scorecard.dev` directly
- **CHAOSS**: the metric definitions themselves. The reference to consult when designing your own metrics
- **Snyk Advisor**: per-package health scores. Mostly a web UI

---

## 7. Sources

- [github/github-mcp-server](https://github.com/github/github-mcp-server)
- [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)
- [Official MCP registry API](https://registry.modelcontextprotocol.io/v0/servers)
- [DeepWiki MCP Server, Devin Docs](https://docs.devin.ai/work-with-devin/deepwiki-mcp)
- [upstash/context7](https://github.com/upstash/context7)
- [Exa MCP](https://exa.ai/docs/reference/exa-mcp) / [Exa Search API](https://exa.ai/docs/reference/search)
- [GitHub REST API: Search](https://docs.github.com/en/rest/search/search)
- [Improved search on the issues dashboard, GitHub Changelog](https://github.blog/changelog/2026-02-26-improved-search-on-the-issues-dashboard/)
- [github/gh-copilot (archived)](https://github.com/github/gh-copilot)
- [Ecosyste.ms](https://ecosyste.ms/) / [Ecosyste.ms API docs](https://docs.ecosyste.ms/)
- [Libraries.io API](https://libraries.io/api)
- [OpenSSF Scorecard API](https://api.scorecard.dev/)
- [deps.dev API v3](https://docs.deps.dev/api/v3/)
- [OSV.dev API](https://google.github.io/osv.dev/api/)
- [Artifact Hub API](https://artifacthub.io/docs/api/)
- [Homebrew formulae API](https://formulae.brew.sh/docs/api/)
- [Hugging Face Hub API](https://huggingface.co/docs/hub/api)
- [Searching for repositories, GitHub Docs](https://docs.github.com/en/search-github/searching-on-github/searching-for-repositories)
- [PulseMCP API v0.1](https://www.pulsemcp.com/api/docs/v0.1)
- [edelauna/github-semantic-search-mcp](https://github.com/edelauna/github-semantic-search-mcp) / [osgrep](https://github.com/Ryandonofrio3/osgrep) / [sturdy-dev/semantic-code-search](https://github.com/sturdy-dev/semantic-code-search)

*Every command in this report was executed in this environment on 2026-09-19 and verified.*
