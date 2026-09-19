# Security Policy

## Reporting a vulnerability

Use GitHub's private reporting form:
**https://github.com/shoei03/oss-discovery/security/advisories/new**

Reports submitted there are visible only to the maintainers. No email address is published for this project,
so please do not open a public issue for anything you believe is sensitive.

Expect an acknowledgement within a week. If a report is valid, the fix and the advisory are published
together.

## What counts as a vulnerability here

This repository contains documents and one Claude Code skill. There is no service to attack and no code that
executes on its own, so the realistic risk is different from a typical software project:

- **A command in the documentation that would harm someone who runs it.** Every command here is meant to be
  copied and executed. A command that deletes data, leaks a token, or sends information somewhere unexpected
  is the most serious defect this project can ship
- **A URL that points somewhere it should not.** The documents and the skill link to APIs and registries by
  URL. A link to a hijacked or typosquatted domain would be a real problem
- **Instructions in the skill that could be turned against the person running it.** `SKILL.md` is read by an
  agent that can execute commands. Content that manipulates the agent into doing something the user did not
  ask for belongs here

Please report any of these privately.

## What does not

- A documented API being down, having changed, or having a rate limit you dislike. That is staleness, not a
  vulnerability. Open an issue with the "Something is out of date" template
- A vulnerability in one of the third-party tools this project documents. Report those to the project that
  owns them. If our documentation recommends something that has become unsafe, that is worth telling us
  about, and an issue is the right place

## Supported versions

Only the current `main` branch is supported. There are no releases to patch and no older versions to
back-port to.
