# Contributing

The value of this project rests on one thing: **everything in it has been measured.**
Hold to that and the rest of the format is negotiable.

Taking part here means following the [Code of Conduct](./CODE_OF_CONDUCT.md).
If you have found something you believe is sensitive, read [SECURITY.md](./SECURITY.md) before opening
an issue.

## Principles

### 1. Run it before you write it

Execute every API call and command on your own machine and confirm what it does.
Including part of the output helps readers tell whether they are reproducing your result.

```bash
# Good: the result is shown
curl -s "https://api.scorecard.dev/projects/github.com/BurntSushi/ripgrep" | jq '.score'
# => 4.7
```

### 2. Never write a capability from guesswork

"It should be able to do this" is how you get it wrong. Read the OpenAPI spec, the official docs,
or the source when they exist.

As a concrete case: an early version of this report claimed the official MCP registry could filter by
transport type. Reading the OpenAPI spec showed no such query parameter exists. That mistake was not
deleted - it is kept in the document as a warning.

### 3. Keep what did not work, and what you rejected

`docs/oss-discovery-tools.md` has a section for things considered and rejected.
If you investigated something and decided against it, add it there **with the reason**.
It is a record that keeps the next person from falling into the same hole.

"I tried it and it did not work" is a genuine contribution here.

### 4. Record the date you verified

Each document carries a measurement date at the top. When you update content, make it clear which
point in time the statement belongs to.

## Contributions that are welcome

- **Reports of stale content** - an API died, a response shape changed. Please include the command you used
- **New registries and data sources** - especially ecosystems outside the ones already covered
- **Workflow improvements** - "this order is faster", "this criterion is missing"
- **Translations** - the documents are currently English only

## Contributions that are not

- Commands that were added without being run
- Performance or capability claims with no source
- Plain lists of tools (awesome-list style additions) - this project is about *how to decide*, not what exists

## Layout

```
docs/oss-discovery-tools.md   The main document: find -> narrow -> evaluate -> read
docs/github-trend-data.md     Trend-tracking data sources (a separate purpose from the main document)
plugins/oss-discovery/skills/oss-discovery/SKILL.md
                              The executable form of the workflow. It is a condensation of the
                              main document, so update it when the main document changes
```

`SKILL.md` is loaded into Claude Code, so keep it terse. Evidence and measurements belong in `docs/`;
`SKILL.md` should only point at them.
