---
name: oss-discovery
description: Use when finding OSS on GitHub that fits a purpose and judging whether to adopt it. Always use for requests like "is there a library that does X?", "find me a tool for X", "should we adopt this library?", or "what are the alternatives to X". Runs four stages - check for a domain registry, narrow with gh search, evaluate real usage and health, then read the internals.
---

# Find OSS and judge whether to adopt it

## First: never send natural language straight to search

GitHub search is an AND search over keywords. A sentence returns nothing.

```bash
gh search repos "a tool that autocompletes SQL when you write in the terminal"   # 0 results
gh search repos --topic=sql --topic=cli --stars=">500" --archived=false          # hits
```

Always translate the request into topics, languages and numeric qualifiers before searching.

---

## Stage 1. Find

### Check for a domain registry first

If what you are looking for belongs to a specific domain (MCP servers, editor extensions, packages in a
particular ecosystem), that domain's registry beats GitHub search. **When you find a registry, treat it not
as a shortcut within stage 1 but as the output of a full pass through the workflow.**

```
Pass 1: target = "the means of searching this domain"
    Stages 1-3 identify the registry.
    Stage 4 clarifies its API and constraints.
    The output is the search mechanism itself.

Pass 2: target = what you actually wanted
    Stage 1 searches using the registry's API, then stages 2-4 as usual.
```

**Do not skip stage 4 and infer capabilities.** If an OpenAPI spec exists, read it. Writing "it should be
able to" is how you get it wrong.

Known registries:

| Target | Registry |
|---|---|
| MCP servers | `https://registry.modelcontextprotocol.io` (publishes OpenAPI), Smithery / Glama / PulseMCP |
| Claude Code plugins and skills | `plugins/` and `external_plugins/` in `anthropics/claude-plugins-official` |
| npm / PyPI and similar packages | ecosyste.ms (see stage 3) |

### With no registry, translate into vocabulary

| Element of the request | Translates to |
|---|---|
| The function in "a tool that does X" | Several `--topic=` values (GitHub Topics is a normalized vocabulary) |
| "in the terminal", "as a CLI" | `--topic=cli`, `--topic=terminal` |
| A stated or inferred language | `--language=` |
| "something solid", "the standard one" | `--stars=">500"` plus `--archived=false` |
| "something still usable" | `--updated=">(six months ago)"` |
| "something recent" | `--created=">(start of this year)"` |

**Split the vocabulary candidates across several queries and merge the results.** Do not try to land it in one.

When no names are known at all, search the web first to pick names out of blog posts and comparisons,
then confirm them on GitHub.

---

## Stage 2. Narrow

```bash
gh search repos --language=<lang> --topic=<topic> \
  --stars=">1000" --updated=">2026-06-01" --archived=false \
  --sort=stars --limit=20 \
  --json fullName,stargazersCount,license,pushedAt,description
```

**Always pass `--archived=false`.** Without it, repositories that stopped years ago dominate the top.

### Confirm development is ongoing, with GraphQL

The Search API cannot return recent commit counts. This is what keeps star counts from fooling you.

```bash
gh api graphql -f query='{ search(query:"<query>", type:REPOSITORY, first:20){ nodes{ ... on Repository {
  nameWithOwner stargazerCount
  licenseInfo{spdxId}
  defaultBranchRef{target{... on Commit{history(since:"2026-06-01T00:00:00Z"){totalCount}}}}
  issues(states:OPEN){totalCount} pullRequests(states:OPEN){totalCount}
}}}}'
```

### Search API limits

- **1,000 results** maximum per query; paging cannot exceed it. Split with ranges like `stars:1000..2000`
- Rate limit **30 req/min** (10 req/min for code search)
- Query length 256 characters; at most five `AND` / `OR` / `NOT` operators combined

---

## Stage 3. Evaluate

### Is it actually used? (more reliable than star count)

```bash
curl -s "https://packages.ecosyste.ms/api/v1/registries/<registry>/packages/<pkg>" \
  | jq '{dependent_repos_count, downloads, rankings}'
```

`rankings` gives the **percentile across all packages (lower is better)**. No authentication required.

Registry names include `npmjs.org`, `pypi.org`, `crates.io`, `rubygems.org`.

### Security health

```bash
curl -s "https://api.scorecard.dev/projects/github.com/<owner>/<repo>" \
  | jq '{score, checks: [.checks[]|{name,score}]}'
```

**Do not cut on the aggregate score.** Excellent single-maintainer projects lose points on review-related
checks (ripgrep scores 4.7 out of 10). Read the individual checks: `Vulnerabilities`, `Dangerous-Workflow`,
`Maintained`, `Signed-Releases`.

### Order of judgement

1. **Is it maintained?** Commits in the last three months above zero, `archived: false`
2. **Is it actually used?** The `dependent_repos_count` percentile
3. **License.** `licenseInfo.spdxId`. `NOASSERTION` needs a closer look
4. **Security.** The individual Scorecard checks
5. Star count. **Look at this last.** Marketing moves it easily

---

## Stage 4. Read

Once the field is narrowed, look inside.

- **An OpenAPI spec or official specification comes first.** Machine-readable, exhaustive, no inference
- **DeepWiki MCP.** Ask questions about any public repository in natural language.
  `claude mcp add -s user -t http deepwiki https://mcp.deepwiki.com/mcp` (no authentication)
- **Context7 MCP.** Once adoption is decided, pull version-specific API references

---

## What not to do

- **Judge on star count alone.** It is the last signal. Do not skip stages 1-3
- **Treat presence in a registry as a quality guarantee.** Listings are self-reported, and excellent
  implementations go unlisted
- **Skip stage 4 and infer what a registry or API can do.** Do not guess at what a spec would tell you
- **Send natural language straight to search.** It returns nothing
- **Omit `--archived=false`.** Dead repositories rise to the top

---

## Evidence

The reasoning behind each choice, the measurements, and the full list of tools considered and rejected
live in
[oss-discovery-tools.md](https://github.com/shoei03/oss-discovery/blob/main/docs/oss-discovery-tools.md).

Trend tracking (which repositories are growing right now) is out of scope for this skill.
For the state of the event data, see
[github-trend-data.md](https://github.com/shoei03/oss-discovery/blob/main/docs/github-trend-data.md).
