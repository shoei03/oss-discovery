# Tools and harnesses for finding OSS

Measured: 2026-09-19 / Environment: macOS (darwin 25.6.0), `gh` 2.97.0 (authenticated)
Purpose: compare the ways to find OSS on GitHub and judge whether to adopt it, for **technical investigation and adoption decisions**.

Every command and API here was actually executed and verified. Things that did not work are recorded too, with the reason.
For an overview of the project and how to install the skill, see the [README](../README.md).

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
| List the leading repositories in a field | **`gh search repos`** | 2. Narrow |
| Keep only repositories that are still alive | **GraphQL** (recent commit counts in one request) | 2. Narrow |
| Decide whether to adopt | **ecosyste.ms packages API** (dependent-count percentile) | 3. Evaluate |
| Check security health | **OpenSSF Scorecard API** | 3. Evaluate |
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

#### The same shape elsewhere

| Target | Registry |
|---|---|
| MCP servers | `https://registry.modelcontextprotocol.io` (official, publishes OpenAPI), Smithery / Glama / PulseMCP |
| Claude Code plugins and skills | `plugins/` and `external_plugins/` in `anthropics/claude-plugins-official` |
| npm / PyPI and similar packages | ecosyste.ms (see section 3.3) |

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
`--include-forks` `--match {name|description|readme}` `--sort {stars|forks|updated|help-wanted-issues}`

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

**OpenSSF Scorecard**:

```bash
curl -s "https://api.scorecard.dev/projects/github.com/BurntSushi/ripgrep" \
  | jq '{score, checks: [.checks[]|{name,score}]}'
```

Measured: ripgrep scores **4.7 out of 10** overall (`Code-Review: 2`, "Found 6/23 approved changesets").

> **How to read it:** ripgrep is an extremely widely used, high-quality project, but its single-maintainer
> model loses points on review-related checks. **Do not cut on the aggregate score**; read the individual
> checks (`Vulnerabilities`, `Dangerous-Workflow`, `Maintained`, `Signed-Releases`).

**Order of judgement:**

1. **Is it maintained?** Commits in the last three months above zero, `archived: false`
2. **Is it actually used?** The `dependent_repos_count` percentile
3. **License.** `licenseInfo.spdxId`. `NOASSERTION` needs a closer look
4. **Security.** The individual Scorecard checks
5. Star count. **Look at this last.** Marketing moves it easily

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
| ecosyste.ms | API | **no** | full | working (weak search) | 3. Evaluate (centrepiece) |
| OpenSSF Scorecard | API | **no** | full | working | 3. Evaluate |
| deps.dev | API | **no** | full | working | 3. Evaluate (dependency graph) |
| Libraries.io | API | yes (free key, 60 req/min) | partial | working | ecosyste.ms alternative |
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
| **Libraries.io** | Coverage and features overlap almost entirely with ecosyste.ms, which needs no authentication. Kept as a fallback |
| **Semantic-search MCP servers** (`github-semantic-search-mcp` 31 stars, `semcode`, `semantic-code-mcp`, `osgrep`) | All search inside repositories that were indexed beforehand. Not a discovery tool |
| **Exa's `category=github`** | No such value exists (`company`, `publication`, `news`, and so on). Use domain narrowing instead |
| **OSS Insight Data Explorer** | A dedicated natural-language-to-SQL harness, but `ossinsight.io/explore` is "under maintenance" |
| **`gh copilot suggest`** | Deprecated 2025-10-25, repository archived, folded into Copilot CLI |
| **OpenHub** | Crawls infrequently; its data goes stale |
| **GH Archive / OSS Insight trend API** | Out of scope here, but for trend work their collection is broken. See [github-trend-data.md](./github-trend-data.md) |

### Other health-evaluation tools

- **deps.dev** (Google): `https://api.deps.dev/v3alpha/systems/npm/packages/<name>`, no authentication.
  Version lists, deprecation flags, dependency graphs. Verified working
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
- [Ecosyste.ms](https://ecosyste.ms/)
- [Libraries.io API](https://libraries.io/api)
- [OpenSSF Scorecard API](https://api.scorecard.dev/)
- [edelauna/github-semantic-search-mcp](https://github.com/edelauna/github-semantic-search-mcp) / [osgrep](https://github.com/Ryandonofrio3/osgrep) / [sturdy-dev/semantic-code-search](https://github.com/sturdy-dev/semantic-code-search)

*Every command in this report was executed in this environment on 2026-09-19 and verified.*
