# Project Rules

Long-lived project memory for `D:\Users\joty79\scripts\encode`.

## Current Scope

- This repo owns legacy PowerShell media helper scripts under `Video/`, `audio/`, `subtitle/`, `icons/`, and `no_audio/`.
- Treat `.ps1` files as script logic and `.reg` files as Windows Explorer context-menu integration artifacts.
- Preserve existing behavior unless a change is explicitly requested.

## Guardrails

- Confirm active repo path before reads/edits: `D:\Users\joty79\scripts\encode`.
- Review `.reg` files carefully before import or edits, especially absolute script paths and wildcard registry keys.
- Do not track runtime queue state, logs, or machine-local generated archives.
- After PowerShell script edits, run parser validation before runtime testing when command execution is allowed.

## Decisions

### 2026-05-07 - Repo onboarding

- Date: 2026-05-07
- Problem: The legacy encode scripts did not have a Git repo or root documentation.
- Root cause: The scripts predate the current repo/documentation workflow.
- Guardrail/rule: Keep root docs minimal, track reusable scripts/integration files, and ignore runtime queue/log state.
- Files affected: `.gitignore`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Initial file inventory and `git status --short`.
