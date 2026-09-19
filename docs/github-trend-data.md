# The state of GitHub trend data

Measured: 2026-09-19 / Environment: macOS (darwin 25.6.0), `gh` 2.97.0 (authenticated)

**How to use this document:** reference material for mechanically tracking which repositories are growing
right now. To find OSS that fits a purpose and judge whether to adopt it, see
[oss-discovery-tools.md](./oss-discovery-tools.md).
For an overview of the project, see the [README](../README.md).

**The short version:** event-derived trend metrics (star-velocity rankings and the like) cannot be trusted as
of 2026. But **activity on GitHub itself has not declined.** Only the collection side is broken, and an
alternative collector exists.

---

## Contents

1. [Conclusion](#1-conclusion)
2. [GH Archive's collection is broken](#2-gh-archives-collection-is-broken)
3. [The alternative: OpenDigger](#3-the-alternative-opendigger)
4. [The state of OSS Insight](#4-the-state-of-oss-insight)
5. [GitHub Trending](#5-github-trending)
6. [Recipe: your own snapshot diffs](#6-recipe-your-own-snapshot-diffs)
7. [Sources](#7-sources)

---

## 1. Conclusion

| What you want | What to use |
|---|---|
| Look at trends with human eyes | **GitHub Trending.** GitHub computes it from internal data and it still works |
| Use event data for analysis | **OpenDigger's archive**, a drop-in replacement for GH Archive |
| Automate your own tracking | **Daily snapshot diffs of `gh search repos`** (see section 6) |
| Analyse history before 2025 | GH Archive is usable, though WatchEvent already degraded from June 2025 |
| **What to avoid** | GH Archive's current data, and the OSS Insight trend API |

---

## 2. GH Archive's collection is broken

Star-velocity rankings and similar metrics draw on GitHub's public events stream (the public events
firehose). That collection is not working.

### The decisive evidence: the same hour through two collectors

OpenDigger has published a GHArchive-compatible independent archive since 2026-09-06. I fetched the same
hour from both, confirmed there were no duplicate event IDs, and compared (`2026-09-14-3` UTC).

| | All events | of which WatchEvent (stars) |
|---|---|---|
| GH Archive | 140,962 | **195** |
| OpenDigger (independent) | 553,349 | **18,173** |
| GH Archive capture rate | about 25% | **about 1%** |

- Neither had duplicate IDs (verified across all rows with `jq -r '.id' | sort -u`)
- On containment: 127,195 in both, 13,767 only in GH Archive, 426,154 only in OpenDigger.
  **Neither is complete**, but the scale of the loss differs by an order of magnitude
- At another hour (`2026-09-17-12`), GH Archive had 75,457 events against OpenDigger's 579,036, a factor of 7.7

**Roughly 99% of star events are missing from GH Archive.**

### Activity on GitHub has not declined

GH Archive recorded 4,864 WatchEvents for the same hour a year earlier (`2025-09-14-3`). On its face that
looks like a fall from 4,864 to 195, but **the true volume has in fact risen**. The independent collector
measures 18,173 today.

> **A note on methodology:** comparing GH Archive against GH Archive's own past cannot reveal the extent of
> the degradation, because the older data was already incomplete. You need an independent collector, or a
> GitHub API such as stargazers, as ground truth.

### For reference: GH Archive over time (the 12:00 hour, compressed size)

| Date | Size |
|---|---|
| 2024-09-17 | 131.6 MB |
| 2025-03-17 | 149.3 MB |
| 2025-09-17 | 81.7 MB |
| 2025-12-17 | 33.7 MB |
| 2026-03-17 | 25.9 MB |
| 2026-06-17 | 21.3 MB |
| 2026-09-17 | 22.9 MB |

Comparing the breakdown by event type, **no type has disappeared** (in fact `DiscussionEvent` is new). Every
type survives and only the counts have fallen, and they have not fallen uniformly: PushEvent to 51% against
WatchEvent at 22% and ForkEvent at 14%, all year-over-year within GH Archive. That is consistent with
collection loss rather than a specification change.

### Independent corroboration

Unresolved issues have piled up in the GH Archive repository.

| Issue | Subject |
|---|---|
| [310](https://github.com/igrigorik/gharchive.org/issues/310) (OPEN, 2025-07) | Drastic Drop Off in Events After 2025-05-23 |
| [312](https://github.com/igrigorik/gharchive.org/issues/312) (CLOSED, 2025-10) | Data size / number of events have dropped 100x since 2025-10-09 |
| [320](https://github.com/igrigorik/gharchive.org/issues/320) (OPEN, 2026-05) | WatchEvent capture rate has degraded significantly since June 2025, **collapsed since Feb 2026** |
| [323](https://github.com/igrigorik/gharchive.org/issues/323) (OPEN, 2026-09) | OpenDigger begins offering an alternative archive |

Issue 320 measures capture rate against GitHub's stargazers API as ground truth and reports a fall "from a
healthy 95-100% baseline to under 20% in 2026". The 1% measured here is harsher still, but the direction agrees.

---

## 3. The alternative: OpenDigger

A drop-in replacement for GH Archive. Swap the hostname; the path convention is identical.

```bash
# Hourly archives (YYYY-MM-DD-H.json.gz)
curl -s "https://gharchive.open-digger.cn/2026-09-14-3.json.gz" | gunzip -c

# Manifest (event count, SHA-256, per-minute breakdown, observation timestamps)
curl -s "https://gharchive.open-digger.cn/2026-09-14-3.manifest.json" \
  | jq '{event_count, compressed_bytes}'
```

**Collection method:** it polls all three pages of GitHub's public Events API and adaptively adjusts the
request interval based on the overlap between consecutive responses. When overlap drops too low it returns to
the fastest interval.

**Constraints:**

- **Hourly files only.** There are no daily or monthly aggregate downloads
- **From 2026-09-06 onward only.** Nothing exists before that
- No BigQuery dataset
- Completeness is not guaranteed. Because the source is the Events API, only a limited recent window is
  visible and there is no durable cursor or replay mechanism. In the measurement above, 13,767 events existed
  only in GH Archive

---

## 4. The state of OSS Insight

### The trend API is down

`GET https://api.ossinsight.io/v1/trends/repos/` returns an empty array with the reason spelled out
(re-fetched to confirm it reproduces).

```json
{
  "data": { "rows": [], "result": { "row_count": 0 } },
  "data_quality": {
    "status": "unavailable",
    "metric": "github_event_derived_ranking",
    "source": "github_public_events_firehose",
    "unavailable_since": "2026-03-01",
    "reason": "...our capture of those events fell to roughly 0.3% of baseline, so the ordering would be noise..."
  }
}
```

That 0.3% is the figure for OSS Insight's own collection pipeline, not for GH Archive. It is the same order
of magnitude as the 1% star capture rate measured here for GH Archive.

### What still works

Totals are synced directly from GitHub and are fine (HTTP 200 confirmed).

```bash
curl -s "https://api.ossinsight.io/gh/repos/BurntSushi/ripgrep" | jq '.data | {stargazers_count, forks_count}'
```

- `/gh/repos/{owner}/{repo}` for totals such as star and fork counts
- `/v1/collections/{id}/repos` for collection membership

Rate limits: 600 req/hour per IP, 1,000 req/min globally. No authentication.

### Data Explorer is down

The feature that turns natural language into SQL and queries GitHub data, built on Chat2Query.
`https://ossinsight.io/explore` currently shows "Data Explorer is under maintenance". It is not a deprecation
notice, but even after it returns the underlying data is still what section 2 describes.

---

## 5. GitHub Trending

`https://github.com/trending?since=weekly`

**GitHub computes this from internal data, so the firehose problem does not touch it.** Confirmed that the
weekly ranking renders normally with "X stars this week" attached. Per-language tabs exist too.

**There is no official API.** To automate, you either scrape or use the snapshot diffs in the next section.

---

## 6. Recipe: your own snapshot diffs

With event-derived rankings unusable, this is **the most reliable way to track over time**. Star totals from
`gh search repos` come straight from GitHub and are accurate.

```bash
# Save a daily snapshot
mkdir -p snapshots
DATE=$(date +%F)
gh search repos --topic=ai-agent --stars=">500" --archived=false \
  --sort=stars --limit=100 --json fullName,stargazersCount \
  > "snapshots/${DATE}.json"

# Diff after some time has passed (verified)
jq -s 'INDEX(.[0][]; .fullName) as $old | .[1][] |
       {repo: .fullName, delta: (.stargazersCount - ($old[.fullName].stargazersCount // .stargazersCount))} |
       select(.delta > 0)' snapshots/2026-09-19.json snapshots/2026-09-26.json \
  | jq -s 'sort_by(-.delta)'
```

To surface newcomers, filter on creation date.

```bash
gh search repos --created=">2026-01-01" --stars=">1000" --archived=false \
  --sort=stars --limit=50 \
  --json fullName,stargazersCount,createdAt,description \
  --jq '.[] | [.stargazersCount, .fullName, .createdAt[0:10], .description] | @tsv'
```

**Constraint:** the Search API caps at 1,000 results per query and 30 req/min. Split what you monitor across
topics or languages (details in the Search API limits section of
[oss-discovery-tools.md](./oss-discovery-tools.md)).

---

## 7. Sources

- [GH Archive](https://data.gharchive.org/). Unresolved issues: [310](https://github.com/igrigorik/gharchive.org/issues/310), [320](https://github.com/igrigorik/gharchive.org/issues/320), [323](https://github.com/igrigorik/gharchive.org/issues/323)
- [OpenDigger GHArchive-compatible archive](https://gharchive.open-digger.cn/), from [OpenDigger](https://open-digger.cn)
- [OSS Insight Public API](https://ossinsight.io/docs/api) / [Explore](https://ossinsight.io/explore)
- [GitHub Trending](https://github.com/trending)
- [GitHub REST API: Search](https://docs.github.com/en/rest/search/search)

*Every command in this document was executed in this environment on 2026-09-19 and verified.*
