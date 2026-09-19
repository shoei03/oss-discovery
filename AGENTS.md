# For agents working in this repository

## What this project is

A repository holding a workflow for finding OSS and deciding whether to adopt it, together with the
measurements that back it up. **Its value rests on everything having been measured.**

## Rules

1. **Run it, confirm it, then write it.** Execute APIs and commands locally and check the output
2. **Never write a capability from guesswork.** If an OpenAPI spec or official documentation exists, read it.
   Do not write "it should be able to"
3. **Keep what did not work, with the reason.** Add it to the "considered and rejected" section of
   `docs/oss-discovery-tools.md`. Do not delete it
4. **Watch how you measure.** Comparing a source against its own past cannot reveal degradation.
   Anchor on an independent ground truth
5. **Record the date you verified**

## Layout

```
README.md                 Entry point: quick reference, install, usage
docs/
  oss-discovery-tools.md  The main document: 1. find, 2. narrow, 3. evaluate, 4. read
  github-trend-data.md    Trend-tracking data sources (separated because the purpose differs)
plugins/oss-discovery/
  .claude-plugin/plugin.json
  skills/oss-discovery/SKILL.md   The executable form of the workflow
.claude-plugin/marketplace.json   Marketplace definition that publishes this repository
```

## When updating

- After changing `docs/oss-discovery-tools.md`, check whether `SKILL.md` needs to follow
  (SKILL.md is a condensation of the main document)
- Links from `SKILL.md` to the documents must use public URLs. When installed as a plugin the skill is
  copied into a cache directory and `docs/` is no longer adjacent to it
- The documents are written in English
