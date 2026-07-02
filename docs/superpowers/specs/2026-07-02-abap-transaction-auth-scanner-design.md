# ABAP Transaction Authorization-Check Scanner — Design

**Date:** 2026-07-02
**Status:** Approved (design + spec review)

## Problem

Users are granted authorization to *start* a transaction, but the meaningful
authorization checks often live deep inside the program logic the transaction
invokes — nested in classes, function modules, and form routines several call
levels down. It is not feasible to exercise every transaction across every edge
case at runtime to discover these checks. We need a **static** way to compute
the code reachable from a transaction and enumerate every authorization check in
it.

## Goal

Produce a **complete inventory** of authorization checks reachable from a given
transaction, with precise locations (`transaction → call path → include →
method/form → line → check type → authorization object`), plus an explicit list
of the blind spots where static analysis cannot see.

This is a **shippable product**: it must run on arbitrary customer S/4 systems,
delivered as an installable add-on, with no dependency on any particular
customer's code.

## Scope

- **Targets:** custom transactions *and* the standard SAP code they reach
  (follow calls across the custom→standard boundary).
- **Check types detected:**
  1. Classic `AUTHORITY-CHECK OBJECT '...' ID ... FIELD ...` statement.
  2. Class-based checks — `CL_ABAP_AUTHORITY_CHECK` and similar S/4 auth APIs.
  3. Authorization function modules — `AUTHORITY_CHECK`, `AUTHORITY_CHECK_TCODE`,
     `VIEW_AUTHORITY_CHECK`, and other `AUTHORITY_CHECK*` wrappers.
- **Out of scope:** CDS/DCL declarative access controls and `S_RFC` handling.

## Central limitation (stated honestly)

Exhaustive static reachability into standard code is not fully solvable. Three
things defeat pure static analysis:

- **Dynamic dispatch** — `CALL FUNCTION lv_fname`, `CALL METHOD lo_ref->(lv_meth)`,
  `SUBMIT (lv_prog)`: the target is not in the source.
- **BAdIs / enhancements / events** — bound at runtime by filter/implementation.
- **Graph explosion** — a custom transaction reaching MM/FI standard can touch
  tens of thousands of objects.

The product therefore delivers a **best-effort static graph with explicit
"unresolved / frontier" markers**, using heuristics where possible and flagging
what remains. No runtime tracing is used.

## Approach decision (A vs B) — settled on evidence

Two substrates were considered for answering "what does this unit call?":

- **A — cross-reference index (chosen).** SAP's pre-built index `WBCROSSGT`
  (method/FM/class/type references) and `CROSS` (`PERFORM` form routines),
  keyed by `INCLUDE`.
- **B — ADT MCP / external orchestration (rejected as primary).**

A read-only feasibility probe against a live system (`HF S/4 Mandant 100`,
transaction `/UCOM/CUSTOMER` → `/UCOM/RP_MAINTAIN_CUSTOMER`) showed:

- The ADT `get_object_dependencies` tool returns **DDIC/type** dependencies, not
  call edges — it did **not** surface `/UCOM/CL_CUSTOMER_FACTORY` despite the code
  calling it. B would have to fetch and parse source at every hop.
- `WBCROSSGT` **did** yield the call edges directly: `OTYPE='ME'` rows are
  method-call edges (e.g. `/UCOM/CL_CUSTOMER_FACTORY\ME:GET_CUSTOMER_ACCESS`,
  `/UCOM/IF_CUSTOMER_UI_MANAGER\ME:SAVE_CUSTOMER`), keyed by include, returned in
  ~30 ms. `NAME` format `OBJECT\ME:METHOD` is cleanly parseable.

Decision: **A** — an in-system ABAP analyzer. It scales into standard code
(the index exists for all activated objects), is fast (indexed, not parsed), and
is the more shippable model. B is retained conceptually only as a possible
alternate edge-provider for edge cases.

**End-to-end validation (manual, live).** The full concept was walked by hand on
`/UCOM/CUSTOMER`: entry report `/UCOM/RP_MAINTAIN_CUSTOMER` (no check) →
`/UCOM/CL_CUSTOMER_FACTORY=>GET_CUSTOMER_ACCESS` → `/UCOM/CL_CUSTOMER_ACCESS`
(reached behind interface `/UCOM/IF_CUSTOMER_ACCESS`) → private method
`CHECK_AUTHORIZATION` → `CALL FUNCTION 'ISU_AUTHORITY_CHECK' x_object = 'E_INSTLN'`.
This confirmed: (a) the real guard sits several hops below the transaction in a
private method, invisible from the entry point; (b) it is a call edge that falls
out of the graph; (c) the object literal is statically recoverable; and (d) it
motivated the FM-argument extraction and interface-dispatch refinements above.

## Architecture

**One algorithm, pluggable edge-provider.** A reachability engine performs a
breadth-first walk of the call graph from the transaction entry point. "What does
this unit call?" is answered behind an **edge-provider interface**; the primary
implementation reads the cross-reference index. The interface allows adding a
source-scan provider later without touching traversal logic.

### The walk

1. **Entry resolution** — transaction → program/class/screen via `TSTC`/`TSTCP`
   (SE93 metadata).
2. **BFS frontier** — for each reached *include*, query the index for outgoing
   edges (`ME` method calls, FM calls, `PERFORM` form routines). Resolve each
   target object to its implementing include:
   - class + method → include via `CL_OO_CLASSNAME_SERVICE` (method-include
     service),
   - function module → function-group include via `TFDIR`,
   - program/form → include directly.
   Enqueue unvisited includes.
3. **Dynamic / BAdI expansion** — BAdI call → active implementations from the
   enhancement registry, enqueued. Dynamic `CALL FUNCTION`/`CALL METHOD` →
   best-effort naming-heuristic candidates. A resolved heuristic candidate **is
   descended into**, but every record derived from it is tagged **provisional**
   (so consumers can distinguish confident edges from guessed ones). Anything
   still unresolved → recorded as a **frontier node** (flagged blind spot), not
   descended.
4. **Visited set + guards** — dedupe by include (this alone prevents infinite
   recursion; cycles are naturally terminated). A **configurable depth cap**
   exists purely as a backstop against pathological chains; default set very high
   (e.g. 100 hops) so it effectively never fires. A **scope toggle**
   (custom-only vs. into-standard) tags the custom→standard boundary crossing;
   **default = into-standard**, since the goal is a complete inventory including
   standard code.
5. **Detection pass** — for each reached include, detect authorization checks and
   attach them to the reaching path.

## Detection of check types

The three types split by detection mechanism:

- **Class-based checks and `AUTHORITY_CHECK*` FMs are call edges** — they fall out
  of the graph. During BFS, whenever a reached target matches a configurable
  **known-auth-API registry** (a maintainable table of classes/methods/FMs that
  constitute authorization checks), record a hit. No source parsing.
  Matching is on the **call-site edge** (the `WBCROSSGT` reference to the auth
  API), so a check is inventoried even when it sits behind a dynamic call whose
  target name is statically known — the target include need not itself be
  successfully resolved/reached for the check to be recorded.
- **The classic `AUTHORITY-CHECK` statement is a keyword, not a call** — detected
  by running `SCAN ABAP-SOURCE` over **only the reached includes** (not the whole
  system), extracting the statement, its `OBJECT`, `ID`/`FIELD` operands, and line
  number.

**Extracting the authorization object from FM/class checks.** Recording "an auth
FM was called" is not enough — the inventory needs the actual authorization
object. For each known auth API the registry stores **which argument carries the
object**, and the detector reads that argument at the call site (from the
cross-reference / a light source read). Example: `ISU_AUTHORITY_CHECK` → `X_OBJECT`,
`AUTHORITY_CHECK` → `OBJECT`. When the argument is a literal or a constant
(the common case, e.g. `lc_object_e_instln VALUE 'E_INSTLN'`), the object is
recovered statically; when it is a runtime variable, the object is reported as
*undetermined* for that call.

**Prefix matching is insufficient — the registry is essential.** Real checks are
frequently domain wrappers whose names do not match `AUTHORITY_CHECK*` (validated
live: `/UCOM/CUSTOMER` guards via `ISU_AUTHORITY_CHECK` on object `E_INSTLN`). The
shipped registry must therefore include known wrappers (`ISU_AUTHORITY_CHECK`,
`AUTHORITY_CHECK`, `AUTHORITY_CHECK_TCODE`, `VIEW_AUTHORITY_CHECK`,
`CL_ABAP_AUTHORITY_CHECK`, …) and remain customer-extensible.

The known-auth-API registry ships pre-filled with SAP-standard entries and is
**customer-extensible**, so shops that wrap `AUTHORITY-CHECK` in a Z-helper class
or FM can register it and have it detected as a check.

## Output model

**Inventory record:**
`transaction · call path (entry → … → unit) · include · method/form · line ·
check type · authorization object (+ ID/FIELD when statically literal)`.

**Frontier report (separate):** unresolved dynamic/BAdI edges with their call
site, so a human knows exactly where the static picture has blind spots.

**Delivery / UI:**
- Executable report with a selection screen (transaction, depth cap, scope toggle),
  ALV output for both the inventory and the frontier list.
- A callable **API class** exposing the same results, so the analysis can be
  scripted, fed to ATC, or integrated into CI.

## Packaging for portability

- One dedicated package under a registered namespace.
- **Distribution phasing:** develop and validate the tool *in-system* first
  (build directly in the package, iterate against real transactions until the
  reachability and detection are trusted). Only once proven, connect the package
  to an **abapGit** repository as the distribution/versioning mechanism. The
  self-contained, standard-only design makes this a clean export with no customer
  code to disentangle.
- Depends only on **standard, always-present infrastructure**: `WBCROSSGT`,
  `CROSS`, `TSTC`/`TSTCP`, `TFDIR`, SEO class/method-include services, the
  enhancement/BAdI registry, and `SCAN ABAP-SOURCE`.
- **No dependency on customer code.**

## Known limits (documented in the product)

- Dynamic calls are resolved only heuristically; residual unknowns are frontier
  nodes.
- Requires a current cross-reference index (objects must be activated).
- `AUTHORITY-CHECK` with a dynamically-built object name yields no literal object.
- Frontier nodes are the documented, explicit blind spots — not silently dropped.

## Components (units, each independently testable)

1. **Entry resolver** — tcode → entry include(s). Depends on `TSTC`/`TSTCP`.
2. **Edge provider (interface + index impl)** — include → outgoing edges. Depends
   on `WBCROSSGT`/`CROSS`.
3. **Object→include resolver** — method/FM/form → implementing include. Depends on
   SEO services / `TFDIR`. Must handle **interface-dispatch hops**: a call to an
   interface method (e.g. `/UCOM/IF_CUSTOMER_ACCESS~RELOAD_CUSTOMER`) resolves to
   the implementing class method(s) — the concrete class is often produced by a
   factory, so map interface method → implementing class(es) via SEO relations
   (`SEOMETAREL`) and enqueue each.
4. **Dynamic/BAdI expander** — dynamic & BAdI edges → candidates + frontier nodes.
   Depends on enhancement registry.
5. **Reachability engine** — BFS orchestration, visited set, guards. Depends on 1–4.
6. **Check detector** — auth-API registry match + `SCAN ABAP-SOURCE` statement
   detection. Depends on the registry table.
7. **Inventory + frontier reporter** — record assembly, ALV, API class.
8. **Auth-API registry (content)** — shipped table, customer-extensible.
