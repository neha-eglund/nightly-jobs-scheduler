# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Context

This repository is part of the **NightlyJobs** platform — an automated system where Claude acts as an autonomous agent to run security and code quality jobs every night. The main Java project lives in `../claude-github-demo/`. This sub-repo (`claude-schedule`) contains scheduling-related work for that platform.

The nightly pipeline runs three jobs in parallel at 02:00 UTC via `nightly-orchestrator.yml`:
- **Pentest**: Claude reads `api-spec/payment-api.yml`, generates attack tests via `PentestSuite`, classifies failures as GitHub issues
- **PR Review**: Claude reads PR diffs against CLAUDE.md rules and posts review verdicts (`--approve`, `--comment`, `--request-changes`)
- **Dependency Audit**: OWASP Dependency-Check + Claude CVE triage → GitHub issues for HIGH/CRITICAL findings
- **Morning Briefing**: Final job that creates a `🌙 Nightly AI Report` GitHub issue summarising all results

## Build and Test Commands

Working directory for all Maven commands: `../claude-github-demo/`

```bash
mvn test                                                  # All non-destructive tests
mvn test -Dgroups=stripe -DexcludedGroups=destructive     # Stripe tests only
mvn test -DexcludedGroups=destructive,stripe              # Payment API tests only
mvn test -Dgroups=auth                                    # Auth-tagged tests only
mvn test -Dtest=PentestSuiteTest                          # Spec-driven suite only
mvn allure:report                                         # HTML report → target/site/allure-maven-plugin/
```

## Architecture

### Test generation flow

`PentestSuiteTest` reads `api-spec/payment-api.yml` at runtime via `OpenApiLoader` and generates a `DynamicContainer` per endpoint, each populated by five template classes:

```
payment-api.yml → OpenApiLoader → List<ApiEndpoint>
                                        │
              ┌─────────────────────────┼───────────────────┐
              ▼                         ▼                   ▼
     HappyFlowTemplates       AuthTestTemplates   AccessControlTestTemplates
     InjectionTestTemplates   ExposureTestTemplates
```

To add/remove an endpoint from the pentest scope, edit `api-spec/payment-api.yml` — no Java changes needed.

### JUnit tag hierarchy

- `stripe` — all 7 classes in `stripe/`; requires separate `STRIPE_API_KEY` credential block
- `spec-driven` — `PentestSuiteTest` (spec-driven `@TestFactory`); must use `-Dgroups=spec-driven` not exclusion-only filters or JUnit Platform silently drops the class
- `auth`, `bola`, `injection`, `ratelimit`, `exposure` — individual concern tags
- `destructive` — requires `TARGET_ENV=sandbox`; gated out of nightly CI

### Reporting pipeline

Two `TestExecutionListener` implementations are auto-registered via `META-INF/services/`:
- `PentestReportSummary` → `target/pentest-reports/summary.txt` and the Actions job summary tab
- `GithubIssueReporter` → creates GitHub issues for High/Medium findings when `PENTEST_CREATE_ISSUES=true`

### Workflow entry points

| Workflow | Trigger | Purpose |
|---|---|---|
| `nightly-orchestrator.yml` | cron 02:00 UTC / `workflow_dispatch` | Single entry point; runs all three jobs in parallel, then morning briefing |
| `nightly-pentest.yml` | called by orchestrator | Two sequential steps: Payment API then Stripe (`if: always()` on Stripe step) |
| `nightly-pr-review.yml` | called by orchestrator | Job 1 lists open PRs; Job 2 reviews each in matrix (max 3 parallel) |
| `nightly-dependency-audit.yml` | called by orchestrator | OWASP scan (NVD cache weekly) + Claude CVE triage |
| `claude-code-review.yml` | PR opened/updated | Auto code review on every PR |
| `claude.yml` | `@claude` mention | Interactive assistant for PRs and issues |

## Configuration

Tests read credentials from environment variables first, then `config/pentest.properties` (git-ignored).

Key env vars: `PENTEST_BASE_URL`, `PENTEST_API_KEY`, `PENTEST_USER_TOKEN`, `PENTEST_ADMIN_TOKEN`, `PENTEST_TEST_ACCOUNT_ID`, `TARGET_ENV` (default: `staging`; use `sandbox` for destructive tests), `PENTEST_PROBE_PARAMS`, `PENTEST_SKIP_OPERATIONS`.

Required GitHub Actions secrets: `ANTHROPIC_API_KEY` (Claude workflows), `NVD_API_KEY` (OWASP scan). Pentest credentials go under environment `pentest-staging`.

## Code Standards

- **Java 24** — Records, Text Blocks, Switch Expressions; `var` for local variables; streams over loops
- **Test naming**: `given_<precondition>_when_<action>_then_<securityOutcome>`
- **Template classes**: `final` with private constructors; stateless utilities only
- **Logging**: SLF4J only — no `System.out.println`
- **Collections**: `List.of()` / `Map.of()` / `Set.of()` for fixed-size; no `new ArrayList<>()` when collection is never mutated
- **`PENTEST_CREATE_ISSUES=true`** must only appear in `nightly-pentest.yml`, never in PR/branch workflows
- All test classes must end in `Test` to be discovered by the Surefire JUnit Platform provider

## Claude Skills (defined in `../SKILLS.md`)

- `/optimize-workflow` — analyzes `.github/workflows/` for performance and security improvements
- `/java-refactor` — proposes JDK 17+ refactorings (Records, Text Blocks, Switch Expressions)
- `/security-audit` — scans for hardcoded secrets, vulnerable dependencies, security anti-patterns
- `/sync-docs` — syncs `README.md` and Javadoc with latest code changes, opens a PR