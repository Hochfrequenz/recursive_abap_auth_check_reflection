# CLAUDE.md

Project-specific guidance for AI agents working in this repository. Adapted from
[`Hochfrequenz/aibap_template_repository`](https://github.com/Hochfrequenz/aibap_template_repository).
Read this alongside [README.md](README.md) and the design spec under
[`docs/superpowers/specs/`](docs/superpowers/specs/).

## What this repo is

The ABAP source of **one** package: a static analyzer that, given a transaction
code, recursively walks the reachable call graph and inventories every
authorization check in it. See the design spec for the full architecture.

## Pick the right MCP for the job

| Task | Prefer |
|---|---|
| Read, write, activate, syntax-check, test ABAP code | `sap-adt` (ADT) |
| Create a new object (`PROG`, `CLAS`, `INTF`, `FUGR`, `MSAG`, `TABL`, `DTEL`, `DOMA`) | `sap-adt` (`create_object`) |
| Transport management (create, assign, release) | `sap-adt` (`transport` group) |
| ATC / ABAP Unit / syntax check | `sap-adt` |
| Pulling a git branch into SAP via abapGit | `sap-desktop` (`sap_abapgit_pull`) |
| Running a transaction, looking at a screen, SE80 abapGit | `sap-desktop` |
| Customizing / table maintenance (SM30 for the registry) | `sap-desktop` |

## Rules of the road

- **Do not hand-write abapGit XML.** Create objects via `create_object`; let SAP
  serialize. Pull back into git via abapGit for review.
- **File naming:** all lowercase for abapGit files (`zcl_auth_scan_engine.clas.abap`).
- **Modern Clean ABAP** (non-negotiable): code we can be proud of, not 30-year-old style. Inline `DATA(...)`, `VALUE #( )`, `NEW #( )`, `CORRESPONDING #( )`, `COND`/`SWITCH`, string templates, functional method calls; class-based exceptions via `RAISING` (not `sy-subrc`); small focused methods; ABAP Doc. No obsolete forms. Reviewed by fresh independent review agents at each small step.
- **Never commit secrets** — `.mcp.json`, `opencode.json`, `systems.json`, PATs are gitignored.
- **Respect the transport system** — every change lands in the project TR; **never
  release the transport without explicit human permission.**
- **Write reviewable commits** — one logical change per commit; PRs explain *why*.

## When things go wrong

- **Syntax error on activate:** fix before moving on. Never commit code that doesn't activate.
- **423 lock errors via ADT:** object locked elsewhere, or stale enqueue. `sap-adt` auto-locks;
  a stateful session usually resolves a persistent 423 on a fresh object you own.
- **abapGit pull fails:** almost always an XML serialization issue — read the error, don't guess.

## Project-specific notes

- **Package:** `ZAUTH_SCAN` (transportable). Package creation is a one-time
  prerequisite — `sap-adt` cannot create packages; create it in SE80/SE21 (or via
  `sap-desktop`) before Task 0.
- **Object prefix:** `ZCL_AUTH_SCAN_*` (classes), `ZIF_AUTH_SCAN_*` (interfaces),
  `ZCX_AUTH_SCAN` (exception), `Z_AUTH_SCAN` (report), `ZAUTH_SCAN_*` (DDIC/message class).
- **System(s):** `HF S/4 Mandant 100` (dev). No QA/prod yet.
- **Style:** Clean ABAP (default — change here if a house style is mandated).
- **Test coverage:** every global class has ABAP Unit tests. Pure-logic classes
  (engine, detector) use test doubles injected through interfaces. DB-touching
  classes (entry resolver, xref edge provider, include resolver) use integration
  tests asserting against **stable, known repository objects** (e.g. the probed
  `/UCOM/RP_MAINTAIN_CUSTOMER` cross-references).
- **Transport discipline:** one transportable TR for the whole tool during dev.
- **Dev workflow:** Workflow A (ADT via `sap-adt`) is the edit loop; SAP is the
  source of truth. abapGit roundtrip into this repo (for PR review) happens once
  the tool is validated — not per task.
- **Deployment:** ship via abapGit only — never transport-BLOB exports.
