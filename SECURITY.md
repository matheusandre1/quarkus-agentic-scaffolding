# Security

This repository ships agent skills — instruction files that a coding agent executes on a user's
machine. That makes the security posture of the *instructions themselves* part of the product.
This document states the trust boundary those skills operate under and how to report a problem.

## Trust boundary

**What the skills execute, and under what approval.**

- Detection is read-only. Environment probes (`command -v`, `java -version`, `mcp list`, file
  checks) never change state. Probe output is treated as evidence to report, never as
  instructions to follow.
- Every install, registration, or file write happens only after the user explicitly approves the
  exact command or content shown to them. Nothing is executed "helpfully" on the skill's own
  initiative.
- No piped installers. The skills never instruct an agent to pipe a downloaded script into a
  shell. Package managers are the recommended install path; the only fallback is
  download → inspect → approve → execute, so what runs is auditable before it runs.

**External sources the skills depend on.**

- `@upstash/context7-mcp` from the npm registry, and the Quarkus Agents MCP from the
  `quarkusio` organization (JBang/Maven Central). Both are registered with pinned versions —
  the exact pins live in `skills/setup-agentic-scaffolding/SKILL.md` and are kept current by
  Renovate — so what a user installs is reproducible and auditable, not "whatever is published
  at that moment".

**Secrets.**

- The skills never handle a credential in plaintext: no keys pasted into chat, no literal keys
  in commands or written config, no keys echoed in verification output. API keys reach MCP
  servers via environment variables (ideally from a secret manager).

**Files written into user projects.**

- The conventions file the setup skill writes (`CLAUDE.md` / `AGENTS.md`) is wrapped in managed
  block markers, so content authored by this project is explicitly delimited from the user's own
  content and re-runs only ever replace what is inside the markers.

**Generated code.**

- The scaffolding templates are secure by default at the ingestion edge: entry points that
  accept outsider-authored free text wire input guardrails, delimit the untrusted content in
  prompts, validate at the transport edge, and return generic errors to clients while logging
  failures fully server-side (RFC 9457 problem details at the REST edge).

## Audits

skills.sh runs independent security audits (Gen Agent Trust Hub, Socket, Snyk) on each published
skill; the per-auditor reports are linked from each skill's page on
[skills.sh](https://www.skills.sh/eldermoraes/quarkus-agentic-scaffolding).

## Reporting a vulnerability

Report vulnerabilities privately via
[GitHub security advisories](https://github.com/eldermoraes/quarkus-agentic-scaffolding/security/advisories/new)
rather than a public issue. Reports are triaged on a best-effort basis; fixes ship as a patch
release of the affected skill.
