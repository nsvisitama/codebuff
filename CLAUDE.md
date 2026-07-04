# CLAUDE.md

Guidance for AI coding assistants (Claude Code and others) working in this repository.

## What this repo is

This is the public mirror of **Codebuff** / **Freebuff**, a multi-agent AI coding assistant.
Codebuff coordinates specialized agents (file picker, planner, editor, reviewer, etc.) instead
of relying on one model for everything. **Freebuff** is the free, ad-supported CLI built on the
same agent framework.

**This public repo is a mirror, not the source of truth.** The private repo is canonical;
accepted public PRs get ported into the private repo and re-exported here later (see
`CONTRIBUTING.md`). Do not add backend, database, billing, deployment, or secret-management code
here — it doesn't belong in the public tree and will not survive the export process.

Key technologies: TypeScript monorepo, **Bun** runtime/package manager, **OpenTUI + React 19**
for the terminal UI, a composable agent runtime, and a public JS/TS SDK.

## Repo map (Bun workspaces)

| Path | Package | Purpose |
|---|---|---|
| `cli/` | `@codebuff/cli` | Terminal UI client (OpenTUI + React 19, Zustand, TanStack Query). Entry: `cli/src/index.tsx` → `cli/src/app.tsx`. |
| `sdk/` | `@codebuff/sdk` | Publishable npm package (`@codebuff/sdk`) — the public agent framework/API used by the CLI and external users. Entry: `sdk/src/index.ts` (`CodebuffClient`, `run.ts`, `impl/agent-runtime.ts`, `tools/`). |
| `common/` | `@codebuff/common` | Shared types, constants, tools, and utilities. `private: true`, no build step — consumed as raw `.ts` via package `exports`. |
| `agents/` | `@codebuff/agents` | Public agent *definitions* (see below). |
| `packages/agent-runtime/` | `@codebuff/agent-runtime` | Core execution engine that runs agent steps against LLMs (`run-agent-step.ts`, `tools/handlers/`, `llm-api/`, `templates/agent-registry.ts`). No build step. |
| `packages/code-map/` | `@codebuff/code-map` | Tree-sitter based source parsing/indexing, with per-language `.scm` tag queries. |
| `packages/llm-providers/` | `@codebuff/llm-providers` | OpenAI-compatible provider adapters for the Vercel AI SDK. |
| `evals/` | `@codebuff/evals` | "Buffbench" evaluation harness — runs agents against real repos and judges results. |
| `freebuff/` | `@codebuff/freebuff` | Freebuff CLI build/release files and e2e tests (excludes the private web app). |
| `scripts/tmux/` | `@codebuff/tmux-scripts` | Shell-script toolkit for driving TUI apps in tmux, used for interactive CLI testing. |

Root path aliases (see `tsconfig.json`): `@codebuff/common/*` → `common/src/*`, `@codebuff/sdk` →
`sdk/src/index.ts`, plus `@codebuff/agent-runtime/*`, `@codebuff/llm-providers/*`,
`@codebuff/code-map/*`, `@codebuff/evals/*`.

## Setup and common commands

Package manager is pinned: `bun@1.3.14` (see `.bun-version` / `engines.bun`). Always use `bun`,
never `npm`/`yarn`/`pnpm`.

```bash
bun install                 # install all workspace deps
bun run dev                 # alias for start-cli: bun --cwd cli dev
bun run dev:freebuff        # same, with FREEBUFF_MODE=true
bun run build:sdk           # build the publishable SDK (sdk/dist)
bun run build:freebuff      # build the Freebuff binary
bun run ci                  # build:sdk && build:freebuff — closest thing to "the CI check"
bun run buffbench           # run the buffbench eval harness
```

Testing:

```bash
bun test                    # root: runs unit tests, excludes *.integration.test.* and freebuff/e2e/**
cd cli && bun test          # cli unit + e2e-*.test.ts + integration-*.test.ts (see below)
cd sdk && bun run test:e2e  # sdk/e2e/{streaming,workflows,custom-agents,features}
cd sdk && bun run test:integration
```

There is **no CI workflow in this public repo** (no `.github/workflows/`) — CI lives in the
private source-of-truth repo. When asked "does this pass CI," run `bun run ci` and the relevant
package's tests/typecheck as the closest available proxy.

## Testing conventions

Full details: `docs/testing.md`, `common/src/testing/TESTING_PATTERNS.md`,
`cli/src/__tests__/README.md`.

- **Prefer dependency injection over `mock.module()`.** Define contracts in
  `common/src/types/contracts/` and inject implementations rather than mocking modules globally.
- Use `spyOn()` only for globals or legacy code that can't be refactored to DI.
- Use the helpers in `@codebuff/common/testing/mock-modules.ts` only for mocking constants.
- React 19 + Bun + RTL's `renderHook()` is unreliable here — test CLI hook behavior via
  component integration tests instead of isolated hook tests.
- **CLI test naming convention** (enforced by a `bun` wrapper that auto-skips when
  prerequisites are missing):
  - `*.test.ts` — plain unit tests.
  - `e2e-*.test.ts` — end-to-end tests; require the SDK to be built first (`cd sdk && bun run build`).
  - `integration-*.test.ts` — require `tmux` installed.
- **Interactive/TUI testing goes through `scripts/tmux/`** (`tmux-start.sh`, `tmux-send.sh`,
  `tmux-capture.sh`, `tmux-stop.sh`, or the unified `tmux-cli.sh`). Session logs land in
  `debug/tmux-sessions/` (YAML), viewable with `bun scripts/tmux/tmux-viewer/index.tsx`.
  Standard tmux `send-keys` drops characters — use bracketed paste
  (`\x1b[200~...\x1b[201~`) when scripting input.
- Root `bunfig.toml` sets `[test] exclude = ["**/*.integration.test.*", "freebuff/e2e/**"]` and
  preloads `sdk/test/setup-env.ts`, so a plain root `bun test` intentionally skips integration
  and Freebuff e2e suites.

## Agent definitions (`agents/`)

Agents are plain TypeScript objects (exported `default`) conforming to `AgentDefinition`
(public, `agents/types/agent-definition.ts`) or the internal `SecretAgentDefinition`. Organized
by role: `base2/` (flagship agent, many model variants generated via a shared
`createBase2(mode, options)` factory — e.g. `base2-free.ts`, `base2-max.ts`, `base2-plan.ts`),
`editor/`, `file-explorer/`, `general-agent/`, `librarian/`, `researcher/`, `reviewer/`,
`thinker/` (incl. `best-of-n`), plus singletons like `base-chat.ts`, `basher.ts`,
`context-pruner.ts`, `tmux-cli.ts`, `browser-use/`.

Common fields: `id`, `publisher`, `displayName`, `model` (OpenRouter slug), `spawnerPrompt`
(tells a parent agent when/how to spawn this one), `inputSchema`/`outputSchema`, `outputMode`
(`'structured_output'` or `'last_message'`), `includeMessageHistory`, `toolNames` (whitelist),
`systemPrompt`, `instructionsPrompt`, and optionally `handleSteps: function* (context)` — a
generator yielding `{ toolName, input }` tool calls, which can yield the sentinel `'STEP_ALL'`
to hand control to the LLM loop for the rest of the turn.

Tools referenced by `toolNames` live in `common/src/tools/` and execute via the SDK +
`packages/agent-runtime`. See `docs/agents-and-tools.md` for shell shims
(`codebuff shims install ...`, `eval "$(codebuff shims env)"`) that let agents be invoked as
direct shell commands.

Agent tests: `agents/__tests__/` (unit) and `agents/e2e/` (model-backed, e.g. `base-deep.e2e.test.ts`).

## Lint, format, and type-check conventions

- **ESLint** (`eslint.config.js`, flat config): enforces `import/order` (grouped, alphabetized,
  blank lines between groups), `@typescript-eslint/consistent-type-imports` (warn), unused
  imports/vars as warnings (`^_`-prefixed names are exempt). Ignores `**/dist`, `**/.next`,
  `**/node_modules`, `agents-graveyard/**`.
  - **Environment access is restricted per package**: `cli/src/**` and `sdk/src/**` each ban
    importing `getProcessEnv`/`processEnv`/`ProcessEnv` from `@codebuff/common/env-process` or
    `@codebuff/common/types/contracts/env`. CLI code must use `getCliEnv()`/`CliEnv`; SDK code
    must use `getSdkEnv()`/`SdkEnv`. Don't reach for raw `process.env` in these packages.
- **Prettier** (`.prettierrc`): no semicolons, single quotes, trailing commas everywhere,
  2-space indent. SQL files use lowercase keywords/postgresql dialect; SVGs use the html parser.
- **TypeScript** (`tsconfig.base.json` + root `tsconfig.json`): `target: ES2022`, `strict: true`,
  `noImplicitReturns`, `noEmit`, `moduleResolution: bundler`, project references across all
  workspace packages. Run `bun run typecheck` inside a package (e.g. `cd common && bun run
  typecheck`) rather than assuming a global one.

## Working in this repo

- Prefer editing files in the packages a public PR is meant to touch: `cli/`, `sdk/`, `common/`,
  `agents/`, `packages/agent-runtime/`, `packages/code-map/`, `packages/llm-providers/`,
  `freebuff/` (excluding its private web app pieces), `scripts/tmux/`, and public docs. Avoid
  introducing backend/database/billing/deployment/secret code.
- `common/` has no build step and is imported as raw TypeScript by other packages — don't add a
  bundler step there without checking every consumer's `exports` map usage.
- When changing agent behavior, check whether the change belongs in a shared `base2` factory
  (`agents/base2/`) vs. a single model variant, since many `base2-*.ts` files are generated from
  one factory function.
- Do not force-push `main`.
- Report security vulnerabilities to `support@codebuff.com`, not public GitHub issues
  (`SECURITY.md`).
