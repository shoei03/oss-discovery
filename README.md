# oss-discovery

**A workflow for finding the right OSS on GitHub and deciding whether you should adopt it.**
Install it as a Claude Code skill and you can hand over a vague request and get back a short list of vetted candidates.

This exists to help you stop picking libraries by star count. It documents how to check, mechanically and
through public APIs, whether a project is actually used and actually maintained.

---

## Quick reference

| What you want | What to use | Stage |
|---|---|---|
| The thing you seek belongs to a specific domain (MCP, plugins, ...) | Run the workflow twice - the first pass outputs a domain registry | 1-4, twice |
| Turn a vague request into candidates | Have the agent translate it into topics / languages | 1. Find |
| You don't know any names at all | Exa (neural search) to surface names | 1. Find |
| List the leading repositories in a field | `gh search repos` | 2. Narrow |
| Keep only repositories that are still alive | GraphQL (recent commit counts in one request) | 2. Narrow |
| Decide whether to adopt | ecosyste.ms packages API (dependent-count percentile) | 3. Evaluate |
| Check security health | OpenSSF Scorecard API | 3. Evaluate |
| Understand a repository's design and implementation | DeepWiki MCP | 4. Read |

---

## Install

### As a Claude Code plugin

```bash
claude plugin marketplace add shoei03/oss-discovery
claude plugin install oss-discovery@oss-discovery
```

### Just the skill, by hand

```bash
git clone https://github.com/shoei03/oss-discovery.git
cp -r oss-discovery/plugins/oss-discovery/skills/oss-discovery ~/.claude/skills/
```

### Install nothing, just read

[docs/oss-discovery-tools.md](./docs/oss-discovery-tools.md) is the whole thing.
Every command can be copied and run as-is.

---

## Usage

Once installed, just ask.

```
> find me an OSS tool that autocompletes SQL in the terminal
```

The skill runs these in order:

1. **Find** - check whether a domain registry exists; if not, translate the request into search
   qualifiers such as `--topic=sql --topic=cli`
2. **Narrow** - list candidates with `gh search repos`, then use GraphQL to count commits over the
   last three months and drop the dead ones
3. **Evaluate** - real dependent-repository counts from ecosyste.ms, individual security checks from Scorecard
4. **Read** - ask DeepWiki MCP about the internals of the surviving candidates

It assumes an authenticated `gh` CLI (`gh auth login`). It also uses `jq` and `curl`.

---

## Documentation

| Document | Contents |
|---|---|
| [docs/oss-discovery-tools.md](./docs/oss-discovery-tools.md) | The main document. The four-stage workflow, tool comparison, recipes, and everything considered and rejected |
| [docs/github-trend-data.md](./docs/github-trend-data.md) | Trend-tracking data sources. Why GH Archive's collection is broken and what to use instead |

---

## The principle behind this project

**Only write down what you have measured.**

- Every API and command here was actually executed and verified
- **Things that did not work, and things that were rejected, are kept along with the reason.** That is
  what stops the next person from repeating the same investigation
- Capabilities are never written from guesswork. If a specification exists (OpenAPI and the like), it gets read

For example, an early version of this document claimed the official MCP registry could filter by transport
type. Reading its OpenAPI spec showed no such parameter exists - you have to filter client-side. That mistake
was not deleted; it is kept in the document as a worked example of what happens when you infer a capability
instead of reading the spec.

See [CONTRIBUTING.md](./CONTRIBUTING.md) for how to contribute.

---

## About point-in-time data

**Measured: 2026-09-19**

Everything here reflects what was measured on that date. Whether an API is alive, its rate limits, and its
response shape can all change. These areas move especially fast:

- MCP registries and servers
- Free tiers and rate limits of individual services
- GitHub's search features (what semantic search covers, for instance)

If you find something out of date, please open an issue or a pull request. Including the date you measured
and the command you used is a big help.

---

## License

[MIT](./LICENSE)
