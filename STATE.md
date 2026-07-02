# Project state & handoff

Snapshot for resuming after a session restart. Read this first, then the spec
(`docs/superpowers/specs/`) and plan (`docs/superpowers/plans/`).

## Decision log (authoritative)

- **Workflow pivot → abapGit (Workflow B).** The ADT write path (aibap.mcp) is
  blocked by a P1 lock bug: every `set_source`/`activate` leaves the object
  "currently editing", and re-edits fail until a manual SM12/SM04 clear. See
  `Hochfrequenz/aibap.mcp#383` and `Hochfrequenz/adtler#58` (both retitled
  `[P1][BLOCKER]`, with our repro comments). So we develop ABAP as **files**
  and pull into SAP via **abapGit**, which bulk-creates/activates server-side
  and avoids per-object ADT edit locks.
- **No Hungarian notation.** Drop `iv_`/`rt_`/`et_`/`es_`/`ev_`/`is_`(struct)/
  `gc_`/`ty_` prefixes. Predicate booleans (`is_standard`, `has_frontier`) stay.
  Functional interfaces: collaborators return a single structure
  (`resolution` / `expansion` / `classification`) instead of tri-state EXPORTING.
- **DOT graph model** (confirmed with user): nodes = code units (report / class
  method / function module / form); auth-check nodes connected by a directed
  edge from their containing code node; directed code→code call edges; frontier
  nodes for unresolved dynamic/BAdI edges. **Deterministic**: emit nodes/edges
  in a sorted canonical order so the DOT is byte-identical per system state.
- **DOT snapshot testing** (to design in Task 10b): generate DOT for test
  transactions, store as snapshots, assert on each run by parsing both sides to
  a canonical graph and comparing (order-insensitive). Open question: a DOT
  parser must stay **self-contained** (no external lib) to honour the
  single-package rule — lean toward a minimal in-repo/in-test parser.
- **One self-contained package `ZAUTH_SCAN`**; ABAP Unit tests ship in-package.

## SAP-side coordinates

- System: HF S/4 Mandant 100. Package: `ZAUTH_SCAN`. Transport: `S4UK903496`.
- All 17 objects already **exist** in SAP (created via ADT):
  - Active & correct: `ZAUTH_SCAN` (MSAG, msgs 001–004), `ZCX_AUTH_SCAN` (clean).
  - Active but **still the Hungarian version** (need the clean rewrite applied):
    `ZIF_AUTH_SCAN_TYPES`, `ZIF_AUTH_SCAN_ENTRY`, `ZIF_AUTH_SCAN_EDGE_PROVIDER`,
    `ZIF_AUTH_SCAN_INCL_RESOLVER`, `ZIF_AUTH_SCAN_EXPANDER`, `ZIF_AUTH_SCAN_DETECTOR`.
  - Empty skeletons (not implemented): classes `ZCL_AUTH_SCAN_ENGINE`,
    `ZCL_AUTH_SCAN_ENTRY_RESOLVER`, `ZCL_AUTH_SCAN_XREF_EDGES`,
    `ZCL_AUTH_SCAN_INCL_RESOLVER`, `ZCL_AUTH_SCAN_EXPANDER`,
    `ZCL_AUTH_SCAN_DETECTOR`, `ZCL_AUTH_SCAN_DOT`, `ZCL_AUTH_SCAN_FACADE`;
    table `ZAUTH_SCAN_API`; report `Z_AUTH_SCAN`.

## Authored sources (clean, no-Hungarian) — ready to apply

`staging/abap/` holds the finished foundation sources: types interface,
exception, and the 5 collaborator interfaces (functional signatures, DOT-ready
`node`/`graph_edge`/`result` types). These are the intended content; apply them
to the abapGit `src/` files once the repo is serialized.

## Progress

- ✅ Foundation (types interface + exception + 5 collaborator interfaces) — clean
  no-Hungarian, active. Delivered via abapGit pull.
- ✅ **Task 3 — engine `ZCL_AUTH_SCAN_ENGINE`**: BFS with visited-set (cycle-safe),
  depth cap, scope boundary, provisional propagation, graph retention, check
  aggregation. **6/6 ABAP Unit tests green.**

## Workflow notes (important)

- Main class/interface source syncs cleanly via **abapGit pull** (edit `src/*.abap`
  → `git push` → `sap_abapgit_pull(repo, trkorr=S4UK903496)`), lock-free.
- **abapGit here does NOT sync `*.clas.testclasses.abap`.** Deliver test includes
  via ADT: `lock_object` → `create_test_include` (first time only) →
  `set_include_source(include='testclasses', source=…)` → `activate_object` →
  `run_unit_tests`. A fresh session locks cleanly. Keep the identical test source
  in git (`src/*.clas.testclasses.abap`) for review + abaplint CI.
- Lock bug only bites when re-editing an already-activated object with an orphaned
  lock; in a fresh session the first lock succeeds.

## End tasks (do after implementation + tests pass)

- Install **abaplint** GitHub Actions CI (https://github.com/abaplint/actions-abaplint),
  add `abaplint.json`, fix until green.
- **Compare vs SUIM**: document how our deep-reachability inventory differs from
  SUIM (which largely reports transaction-start / SU24-level auth, not nested checks).
- Add a **mermaid diagram** to the README: high-level tool flow, contrasted with
  what SUIM checks in the same diagram.

## Next steps (post-restart, Workflow B)

1. **Provide a valid GitHub PAT** (the MCP env PAT is expired) and **register
   `ZAUTH_SCAN` as an abapGit online repo** in SAP, linked to this git repo,
   branch **main** (single branch).
2. **Serialize** existing SAP objects → git (SAP-side abapGit) to get correct
   `src/*.abap` + `*.xml`. (SAP owns XML — do not hand-write it.)
3. **Apply** the clean sources from `staging/abap/` to the serialized `src/`
   `.abap` files (foundation), then implement the classes per the plan (TDD via
   ABAP Unit; acceptance: recover `E_INSTLN` from `/UCOM/CUSTOMER` and
   `B_EMMA_CAS` from `EMMACL`).
4. **Iterate**: edit files locally → `git push` → `sap_abapgit_pull` → verify.
