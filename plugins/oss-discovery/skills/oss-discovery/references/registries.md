# Domain registries

Verified: 2026-09-19. Every endpoint below was executed and its status code recorded.
Re-run `scripts/check-sources.sh` to find out what has rotted since.

This file is a **cache of measurements, not a catalogue**. Package ecosystems do not belong here at all -
they are enumerable at runtime (see "Package ecosystems" below). Only domains with no meta-API are listed,
and each row carries what it gives you that `gh search repos` cannot.

---

## Package ecosystems - do not hardcode, list them

```bash
curl -s "https://packages.ecosyste.ms/api/v1/registries" \
  | jq -r '.[] | "\(.name)\t\(.ecosystem)\t\(.packages_count)"' | sort -t$'\t' -k3 -rn
# 100 registries. npmjs.org/npm 5,875,202 - proxy.golang.org/go 2,359,001 -
# hub.docker.com/docker 1,002,713 - pypi.org 936,154 - nuget.org 854,022 -
# repo1.maven.org 624,857 - packagist.org - crates.io - rubygems.org - nixpkgs -
# cocoapods.org - pub.dev - metacpan.org - alpine - debian - ubuntu - ...
```

Pick the registry by `ecosystem`, then look the package up at
`/api/v1/registries/<name>/packages/<pkg>`. There is no reason to write a list of package registries
into a skill.

---

## Cross-ecosystem (use these before any domain registry)

| Registry | Endpoint | Auth | 2026-09-19 | What it gives you that GitHub search cannot |
|---|---|---|---|---|
| **deps.dev** (Google) | `api.deps.dev/v3/projects/github.com%2F<owner>%2F<repo>` | none | 200 | **OpenSSF Scorecard embedded** (`scorecard.overallScore`, per-check scores), license, stars in one call. `v3/systems/<sys>/packages/<pkg>/versions/<v>` adds `isDeprecated` + `deprecatedReason` |
| deps.dev dependents | `api.deps.dev/v3alpha/.../versions/<v>:dependents` | none | 200 | **Per-version** dependent counts. react 18.2.0 -> 13,438; vitest 5.0.1 -> 91. See the warning below |
| **summary.ecosyste.ms** | `summary.ecosyste.ms/api/v1/projects/lookup?url=https://github.com/<o>/<r>` | none | 200 | One call for repo metadata + `commits.dds` + packages + dependencies + `repository.metadata.files` (is there a SECURITY.md / CODEOWNERS / CHANGELOG) |
| **commits.ecosyste.ms** | `commits.ecosyste.ms/api/v1/hosts/GitHub/repositories/<o>%2F<r>` | none | 200 | `dds` (Development Distribution Score - the bus factor), `total_committers`, bot-commit split |
| **issues.ecosyste.ms** | `issues.ecosyste.ms/api/v1/hosts/GitHub/repositories/<o>%2F<r>` | none | 200 | `avg_time_to_close_pull_request` / `_issue` in seconds. vitest: PR 1,160,654s (13.4 days) |
| **packages.ecosyste.ms** | `.../registries/<reg>/packages/<pkg>` | none | 200 | `rankings` - percentile across all packages, lower is better. Still the best "is it actually used" signal |
| **OSV.dev** | `POST api.osv.dev/v1/query`, `/v1/querybatch` | none | 200 | Known vulnerabilities for an exact version. `querybatch` judges a whole candidate list at once |
| OpenSSF Scorecard | `api.scorecard.dev/projects/github.com/<o>/<r>` | none | 200 / 404 | Freshest Scorecard, but **404 for anything not already scanned** |

**deps.dev `:dependents` is version-scoped and is not a popularity metric.** A freshly released version
has almost no dependents no matter how popular the package is. For adoption breadth use
`packages.ecosyste.ms` `rankings` / `dependent_packages_count` instead.

**Scorecard coverage is the same wherever you fetch it from.** Measured: `BurntSushi/ripgrep` returns 4.7
from both `api.scorecard.dev` and deps.dev, but `tconbeer/harlequin` and `sxyazi/yazi` are 404 on
Scorecard *and* carry no `scorecard` field on deps.dev. deps.dev is still preferable because it returns
200 with the rest of the metadata instead of failing the whole call - it does not widen coverage.

---

## Domains with no meta-API

### MCP servers

| Registry | Endpoint | Auth | 2026-09-19 | Size |
|---|---|---|---|---|
| Official MCP registry | `registry.modelcontextprotocol.io/v0.1/servers` (`/v0` still answers) | none | 200 | cursor pagination, no total. `limit` max 100 |
| Smithery | `registry.smithery.ai/servers?q=&pageSize=` | none | 200 | 15,579. Carries `useCount` and `verified` |
| GitHub MCP Registry | `api.mcp.github.com/v0/servers?search=&limit=` | none | 200 | 252. Small but curated; embeds `repository.readme` |
| Docker MCP Catalog | `hub.docker.com/v2/repositories/mcp/` | none | 200 | 245 images, with `pull_count` |
| ~~Glama~~ | `glama.ai/api/mcp/v1/servers` | **API key** | **401** | The API Data License also demands visible Glama attribution on every page that displays the data |
| ~~PulseMCP~~ | `api.pulsemcp.com/v0beta/servers` | - | **410** | `API_SUNSET`: "September 2026: Fully sunset (100%)". v0.1 exists but needs `X-API-Key` |

The official registry's `search` is a **substring match on the server name only** - descriptions are never
searched, so a word that appears only in a description returns 0 results.

### Claude Code plugins and skills

`anthropics/claude-plugins-official` - read `.claude-plugin/marketplace.json`, not the directory listing.
**310 entries** (161 `url`, 97 `git-subdir`, 38 `./plugins/`, 14 `./external_plugins/`) against
39 + 14 directories on disk: counting directories understates it by a factor of six.
A `renames` map is in there too, so old plugin names still resolve.

`anthropics/skills` - 177,072 stars. Holds `skills/`, plus `spec/` and `template/`.

### Kubernetes, Helm, cloud native

| Registry | Endpoint | Auth | 2026-09-19 | What it gives you |
|---|---|---|---|---|
| **Artifact Hub** | `artifacthub.io/api/v1/packages/search?ts_query_web=<q>&limit=` | none | 200 | `security_report_summary` (critical/high/medium/low CVE counts) plus `signed`, `official`, `cncf` **in the search result itself** |
| CNCF Landscape | `landscape.cncf.io/data/full.json` | none | 200 | graduated / incubating / sandbox maturity |
| LF AI & Data | `landscape.lfai.foundation/data/full.json` | none | 200 | same landscape2 schema |

### CLI tools - real install counts, not stars

| Registry | Endpoint | Auth | 2026-09-19 | What it gives you |
|---|---|---|---|---|
| **Homebrew analytics** | `formulae.brew.sh/api/analytics/install/365d.json` (`30d`, `90d`) | none | 200 | **Absolute install counts.** 87,641 formulae / 271,759,233 installs over the year. gh #7 at 2,936,639, ripgrep #91 at 713,784, fd #264 at 217,444 |
| Homebrew formula | `formulae.brew.sh/api/formula/<name>.json` | none | 200 | version, license, bottles |
| Arch AUR | `aur.archlinux.org/rpc/v5/info?arg[]=<pkg>` | none | 200 | `NumVotes`, `Popularity`, `OutOfDate`, `Maintainer` |
| Debian popcon | `popcon.debian.org/by_inst` | none | 200 | plain text install counts from the Linux side |

### ML / LLM - GitHub search is close to useless here

| Registry | Endpoint | Auth | 2026-09-19 | What it gives you |
|---|---|---|---|---|
| **Hugging Face Hub** | `huggingface.co/api/models\|datasets\|spaces?search=&limit=` | none | 200 | `downloads`, `likes`, `trendingScore`, `pipeline_tag` |

### IaC, editor extensions, containers

| Registry | Endpoint | Auth | 2026-09-19 | What it gives you |
|---|---|---|---|---|
| Terraform Registry | `registry.terraform.io/v2/providers/<id>`, `/v1/modules` | none | 200 | provider download totals (aws: 7,652,429,482) |
| Ansible Galaxy | `galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/` | none | 200 | 4,540 collections |
| **Open VSX** | `open-vsx.org/api/-/search?query=&size=` | none | 200 | `downloadCount`, `averageRating`, `deprecated`. Official REST with a Swagger UI |
| VS Code Marketplace | `POST marketplace.visualstudio.com/_apis/public/gallery/extensionquery` | none | 200 | needs `Accept: application/json;api-version=7.2-preview.1`, `filterType:8` |
| JetBrains Marketplace | `plugins.jetbrains.com/api/searchPlugins?search=&max=` | none | 200 | `downloads`, `rating`, `pricingModel` |
| Docker Hub | `hub.docker.com/v2/search/repositories?query=&page_size=` | none | 200 | `pull_count` (nginx: 13,378,876,658), `is_official` |

### Curated lists

`awesome.ecosyste.ms/api/v1/lists` turns awesome-* lists into machine-readable projects with repository
metadata attached. Its `query` parameter filters weakly - treat it as a listing, not a search.

---

## Gotchas (all of these were hit while measuring)

- `repos.ecosyste.ms` wants `hosts/GitHub/repositories/OWNER/REPO` with a raw slash. `OWNER%2FREPO` is 404.
  `commits.` and `issues.` are the opposite and want `%2F`
- `summary.ecosyste.ms` returns `.issues` as a bare `{table: ...}` stub with nulls in it. For issue and PR
  close times you must call `issues.ecosyste.ms` separately
- `summary.ecosyste.ms` `score` (ripgrep 37.3, vitest 39.8) is **ecosyste.ms's own score, not Scorecard**.
  Do not read it on Scorecard's 0-10 scale
- `crates.io` rejects requests without a User-Agent - measured 403
- Terraform v2 needs `page[size]` percent-encoded as `page%5Bsize%5D` or it returns nothing
- CNCF / LF AI serve JSON at `/data/full.json` only. `/data/items.json` and `/api/ids` return SPA HTML
- Homebrew analytics `count` is a **comma-separated string** (`"5,555,454"`), not a number
- The official MCP registry emits unescaped control characters that make `jq` fail mid-pagination, and its
  cursor values can contain spaces, so URL-encode them
