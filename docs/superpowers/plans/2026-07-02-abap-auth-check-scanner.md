# ABAP Transaction Authorization-Check Scanner — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an in-system ABAP tool that, given a transaction code, recursively walks the reachable call graph and produces a complete inventory of every authorization check (classic statement, class-based, and auth function modules) with its location and authorization object.

**Architecture:** One reachability engine (BFS over includes) with pluggable collaborators behind interfaces: an entry resolver, a cross-reference edge provider (`WBCROSSGT`/`CROSS`), an object→include resolver (handles interface dispatch), a dynamic/BAdI expander, and a check detector (registry match + `SCAN ABAP-SOURCE` + FM-argument object extraction). A facade wires the concrete implementations; a report renders ALV output. See the design spec: `docs/superpowers/specs/2026-07-02-abap-transaction-auth-scanner-design.md`.

**Tech Stack:** ABAP (Clean ABAP style), ABAP Unit, ADT via the `sap-adt` MCP (Workflow A). Package `ZAUTH_SCAN` on `HF S/4 Mandant 100`. abapGit roundtrip into this repo for PR review once validated.

---

## Conventions for every task

- **Edit loop (Workflow A):** create with `sap-adt create_object` → write source with `set_source_from_file`/`patch_source` → `syntax_check` → `activate_object` → `run_unit_tests`. SAP is the source of truth; do **not** hand-write abapGit XML.
- **Transport:** all objects go into the single project TR created in Task 0. Never release it without explicit human permission.
- **"Commit" step meaning:** because git source commit is deferred to the abapGit roundtrip (Task 12), each task's definition of done is **activated + green ABAP Unit + clean ATC**. The git repo receives per-task progress only as plan checkbox updates until Task 12.
- **Naming:** classes `ZCL_AUTH_SCAN_*`, interfaces `ZIF_AUTH_SCAN_*`, exception `ZCX_AUTH_SCAN`, DDIC/message class `ZAUTH_SCAN_*`, report `Z_AUTH_SCAN`. abapGit filenames all-lowercase.
- **Test design:** pure-logic classes (engine, detector-parsing) are unit-tested with injected fakes. DB/repository-touching classes (entry resolver, edge provider, include resolver) are integration-tested against the **stable known objects** from the live probe (values below are real and asserted verbatim).

---

## File / object structure

| Object | Type | abapGit file | Responsibility |
|---|---|---|---|
| `ZAUTH_SCAN` | MSAG | `src/zauth_scan.msag.xml` | Message class (errors/texts) |
| `ZIF_AUTH_SCAN_TYPES` | INTF | `src/zif_auth_scan_types.intf.abap` | Shared types (refs, edges, nodes, checks, frontier, result) |
| `ZCX_AUTH_SCAN` | CLAS | `src/zcx_auth_scan.clas.abap` | Exception class |
| `ZIF_AUTH_SCAN_ENTRY` | INTF | `src/zif_auth_scan_entry.intf.abap` | tcode → seed includes |
| `ZIF_AUTH_SCAN_EDGE_PROVIDER` | INTF | `src/zif_auth_scan_edge_provider.intf.abap` | include → outgoing call edges |
| `ZIF_AUTH_SCAN_INCL_RESOLVER` | INTF | `src/zif_auth_scan_incl_resolver.intf.abap` | edge target → implementing include(s) |
| `ZIF_AUTH_SCAN_EXPANDER` | INTF | `src/zif_auth_scan_expander.intf.abap` | dynamic/BAdI edge → candidates + frontier |
| `ZIF_AUTH_SCAN_DETECTOR` | INTF | `src/zif_auth_scan_detector.intf.abap` | classify edge + scan include for checks |
| `ZCL_AUTH_SCAN_ENGINE` | CLAS | `src/zcl_auth_scan_engine.clas.abap` | BFS orchestration (core) |
| `ZCL_AUTH_SCAN_ENTRY_RESOLVER` | CLAS | `src/zcl_auth_scan_entry_resolver.clas.abap` | `ZIF_AUTH_SCAN_ENTRY` via TSTC/TSTCP |
| `ZCL_AUTH_SCAN_XREF_EDGES` | CLAS | `src/zcl_auth_scan_xref_edges.clas.abap` | `ZIF_AUTH_SCAN_EDGE_PROVIDER` via WBCROSSGT/CROSS |
| `ZCL_AUTH_SCAN_INCL_RESOLVER` | CLAS | `src/zcl_auth_scan_incl_resolver.clas.abap` | `ZIF_AUTH_SCAN_INCL_RESOLVER` via SEO/TFDIR |
| `ZCL_AUTH_SCAN_EXPANDER` | CLAS | `src/zcl_auth_scan_expander.clas.abap` | `ZIF_AUTH_SCAN_EXPANDER` via BAdI registry + heuristics |
| `ZAUTH_SCAN_API` | TABL | `src/zauth_scan_api.tabl.xml` | Registry of known auth APIs (+object-arg rule) |
| `ZCL_AUTH_SCAN_DETECTOR` | CLAS | `src/zcl_auth_scan_detector.clas.abap` | `ZIF_AUTH_SCAN_DETECTOR` via registry + SCAN ABAP-SOURCE |
| `ZCL_AUTH_SCAN_FACADE` | CLAS | `src/zcl_auth_scan_facade.clas.abap` | Wires impls; public `run()` API |
| `Z_AUTH_SCAN` | PROG | `src/z_auth_scan.prog.abap` | Selection screen + ALV rendering |

---

## Task 0: Foundations — package, transport, message class

**Prerequisite (human/GUI):** package `ZAUTH_SCAN` (transportable) must exist. `sap-adt` cannot create packages — create it in SE80/SE21 (or via `sap-desktop`) first.

- [ ] **Step 1: Select system**

Run: `sap-adt select_system` with `HF S/4 Mandant 100`.
Expected: active system confirmed.

- [ ] **Step 2: Create the project transport**

Run: `sap-adt create_transport` with description `ZAUTH_SCAN – recursive auth-check scanner`.
Expected: a workbench TR is returned; record its ID as the project TR for all later tasks.

- [ ] **Step 3: Create the message class**

Run: `sap-adt create_object` type `MSAG` name `ZAUTH_SCAN`, package `ZAUTH_SCAN`, TR = project TR.
Then `set_messages` with initial texts: `001 Transaction & not found`, `002 No entry point for transaction &`, `003 Scan aborted: &`.
Run: `activate_object`.
Expected: message class active.

- [ ] **Step 4: Definition of done**

Package holds an active message class assigned to the project TR. No unit tests (content object).

---

## Task 1: Shared types + exception

**Files:** Create `ZIF_AUTH_SCAN_TYPES` (INTF), `ZCX_AUTH_SCAN` (CLAS).

- [ ] **Step 1: Create `ZIF_AUTH_SCAN_TYPES`**

Run: `sap-adt create_object` type `INTF` name `ZIF_AUTH_SCAN_TYPES`, package `ZAUTH_SCAN`, TR.
Source (types only):

```abap
INTERFACE zif_auth_scan_types PUBLIC.

  TYPES:
    "! kind of graph edge
    ty_edge_kind   TYPE c LENGTH 1.           " M=method C=func-call P=perform I=intf D=dynamic B=badi
  CONSTANTS:
    BEGIN OF gc_edge_kind,
      method  TYPE ty_edge_kind VALUE 'M',
      func    TYPE ty_edge_kind VALUE 'C',
      perform TYPE ty_edge_kind VALUE 'P',
      intf    TYPE ty_edge_kind VALUE 'I',
      dynamic TYPE ty_edge_kind VALUE 'D',
      badi    TYPE ty_edge_kind VALUE 'B',
    END OF gc_edge_kind.

  CONSTANTS:
    BEGIN OF gc_check_type,
      statement TYPE c LENGTH 1 VALUE 'S',    " classic AUTHORITY-CHECK
      class     TYPE c LENGTH 1 VALUE 'K',    " class-based
      func      TYPE c LENGTH 1 VALUE 'F',    " AUTHORITY_CHECK* / wrapper FM
    END OF gc_check_type.

  CONSTANTS:
    BEGIN OF gc_scope,
      custom_only   TYPE c LENGTH 1 VALUE 'C',
      into_standard TYPE c LENGTH 1 VALUE 'S',   " default
    END OF gc_scope.

  TYPES:
    BEGIN OF ty_object_ref,
      otype    TYPE string,      " ME / FUNC / FORM / TY ...
      object   TYPE string,      " class / interface / program / FUGR
      sub_name TYPE string,      " method / form / FM name
      raw      TYPE string,      " raw WBCROSSGT NAME
    END OF ty_object_ref,

    BEGIN OF ty_edge,
      source_include TYPE progname,
      kind           TYPE ty_edge_kind,
      target         TYPE ty_object_ref,
    END OF ty_edge,
    ty_edges TYPE STANDARD TABLE OF ty_edge WITH EMPTY KEY,

    BEGIN OF ty_node,
      include       TYPE progname,
      depth         TYPE i,
      is_standard   TYPE abap_bool,
      is_provisional TYPE abap_bool,
      path          TYPE string,          " entry → … → include
    END OF ty_node,
    ty_nodes TYPE STANDARD TABLE OF ty_node WITH EMPTY KEY,

    BEGIN OF ty_check,
      check_type     TYPE c LENGTH 1,
      auth_object    TYPE string,         " '' when undetermined
      object_known   TYPE abap_bool,
      details        TYPE string,         " ID/FIELD text or method/FM
      include        TYPE progname,
      unit_name      TYPE string,         " method / form
      line           TYPE i,
      path           TYPE string,
      is_provisional TYPE abap_bool,
    END OF ty_check,
    ty_checks TYPE STANDARD TABLE OF ty_check WITH EMPTY KEY,

    BEGIN OF ty_frontier,
      source_include TYPE progname,
      kind           TYPE ty_edge_kind,
      reason         TYPE string,
      raw            TYPE string,
      path           TYPE string,
    END OF ty_frontier,
    ty_frontiers TYPE STANDARD TABLE OF ty_frontier WITH EMPTY KEY,

    BEGIN OF ty_result,
      tcode      TYPE tcode,
      checks     TYPE ty_checks,
      frontier   TYPE ty_frontiers,
      nodes_seen TYPE i,
      max_depth_hit TYPE abap_bool,
    END OF ty_result.

ENDINTERFACE.
```

Run: `syntax_check`, then `activate_object`.
Expected: active, no syntax errors.

- [ ] **Step 2: Create `ZCX_AUTH_SCAN`**

Run: `sap-adt create_object` type `CLAS` name `ZCX_AUTH_SCAN` (superclass `CX_STATIC_CHECK`), package, TR. Add a `TEXTID`-style constructor with `MSGID/MSGNO/MSGV1..4` mapping to message class `ZAUTH_SCAN`.
Run: `syntax_check`, `activate_object`.

- [ ] **Step 3: Definition of done** — both objects active.

---

## Task 2: Collaborator interfaces

**Files:** Create the five collaborator interfaces. Interfaces only — activation is the whole test.

- [ ] **Step 1: `ZIF_AUTH_SCAN_ENTRY`**

```abap
INTERFACE zif_auth_scan_entry PUBLIC.
  "! Resolve a transaction to its seed include(s).
  METHODS resolve
    IMPORTING iv_tcode         TYPE tcode
    RETURNING VALUE(rt_includes) TYPE STANDARD TABLE OF progname WITH EMPTY KEY
    RAISING   zcx_auth_scan.
ENDINTERFACE.
```

- [ ] **Step 2: `ZIF_AUTH_SCAN_EDGE_PROVIDER`**

```abap
INTERFACE zif_auth_scan_edge_provider PUBLIC.
  "! All outgoing call edges from one include (method calls, FM calls, PERFORMs).
  METHODS get_edges
    IMPORTING iv_include      TYPE progname
    RETURNING VALUE(rt_edges) TYPE zif_auth_scan_types=>ty_edges.
ENDINTERFACE.
```

- [ ] **Step 3: `ZIF_AUTH_SCAN_INCL_RESOLVER`**

```abap
INTERFACE zif_auth_scan_incl_resolver PUBLIC.
  "! Resolve an edge target to the include(s) that implement it.
  "! Interface-method targets expand to all implementing classes.
  METHODS resolve
    IMPORTING is_edge            TYPE zif_auth_scan_types=>ty_edge
    EXPORTING et_includes        TYPE STANDARD TABLE OF progname WITH EMPTY KEY
              ev_unresolved      TYPE abap_bool.
ENDINTERFACE.
```

- [ ] **Step 4: `ZIF_AUTH_SCAN_EXPANDER`**

```abap
INTERFACE zif_auth_scan_expander PUBLIC.
  "! Expand a dynamic/BAdI edge to provisional candidate includes; anything
  "! left unresolved is returned as a frontier record.
  METHODS expand
    IMPORTING is_edge       TYPE zif_auth_scan_types=>ty_edge
    EXPORTING et_includes   TYPE STANDARD TABLE OF progname WITH EMPTY KEY
              es_frontier   TYPE zif_auth_scan_types=>ty_frontier
              ev_has_frontier TYPE abap_bool.
ENDINTERFACE.
```

- [ ] **Step 5: `ZIF_AUTH_SCAN_DETECTOR`**

```abap
INTERFACE zif_auth_scan_detector PUBLIC.
  "! Is this edge target a known auth API? If so return the check (object filled
  "! from the call arguments when statically recoverable).
  METHODS classify_edge
    IMPORTING is_edge       TYPE zif_auth_scan_types=>ty_edge
    EXPORTING es_check      TYPE zif_auth_scan_types=>ty_check
              ev_is_check   TYPE abap_bool.
  "! Scan one include for classic AUTHORITY-CHECK statements.
  METHODS scan_include
    IMPORTING iv_include     TYPE progname
    RETURNING VALUE(rt_checks) TYPE zif_auth_scan_types=>ty_checks.
ENDINTERFACE.
```

Run for each: `syntax_check`, `activate_objects` (batch).
- [ ] **Step 6: Definition of done** — all five interfaces active.

---

## Task 3: Reachability engine (CORE) — TDD with fakes

The engine is pure orchestration and fully unit-testable with fake collaborators. Build it now to lock the algorithm before touching the database.

**Files:** Create `ZCL_AUTH_SCAN_ENGINE` (CLAS) + local test class (test include).

**Engine contract:** constructor injects the four collaborators + entry resolver. `run( iv_tcode, iv_max_depth = 100, iv_scope = into_standard )` returns `ty_result`.

**Algorithm (BFS):**
1. `seed = entry->resolve( tcode )`; enqueue each seed at depth 0, path = tcode.
2. While queue not empty: pop node. If include already visited → skip. Mark visited.
3. If `depth > max_depth` → set `max_depth_hit`, add frontier "depth cap", do not expand.
4. `checks += detector->scan_include( node-include )` (attach node path/provisional).
5. `edges = edge_provider->get_edges( node-include )`.
6. For each edge: `detector->classify_edge` → if check, append (carry `is_provisional` from node).
7. Resolve targets to includes:
   - kinds M/C/P/I → `incl_resolver->resolve`; if `ev_unresolved` → frontier.
   - kinds D/B → `expander->expand` → provisional candidate includes + optional frontier.
8. For each resolved include: compute `is_standard`. **Classification rule:** an object is *custom* if its name starts with `Z`/`Y` **or** is in a registered customer/partner namespace (`/…/`, e.g. `/UCOM/`); everything else is *SAP-standard*. (Determine authoritatively from the object's package/software component via `TADIR`+`TDEVC` rather than name alone where possible; the name rule is the fallback.) Thus `/UCOM/*` counts as custom — so under `custom_only` the `/UCOM/CUSTOMER` chain is still fully walked, and the boundary frontier is recorded only when crossing into genuine SAP-standard packages. If `scope = custom_only` and target is standard → record boundary frontier, do not enqueue; else enqueue at `depth+1`, `is_provisional = node.is_provisional OR expander-provisional`, path = `node.path & ' → ' & target`.
9. Return result with `nodes_seen = |visited|`.

- [ ] **Step 1: Write failing test — seed with no edges yields the seed's own statement check**

Test include with local `DOUBLE`s implementing the five interfaces. Fake entry returns `('ZTEST_SEED')`; fake edge provider returns no edges; fake detector `scan_include` returns one statement check for `ZTEST_SEED` on object `S_DEVELOP`.

```abap
METHOD one_node_one_statement.
  DATA(lo_engine) = new_engine( ).            " helper wires fakes
  DATA(ls_result) = lo_engine->run( iv_tcode = 'ZT1' ).
  cl_abap_unit_assert=>assert_equals( act = lines( ls_result-checks ) exp = 1 ).
  cl_abap_unit_assert=>assert_equals( act = ls_result-checks[ 1 ]-auth_object exp = 'S_DEVELOP' ).
  cl_abap_unit_assert=>assert_equals( act = ls_result-nodes_seen exp = 1 ).
ENDMETHOD.
```

- [ ] **Step 2: Run test — expect FAIL** (class not implemented).
Run: `sap-adt run_unit_tests` on `ZCL_AUTH_SCAN_ENGINE`. Expected: FAIL/compile error.

- [ ] **Step 3: Implement minimal engine** to pass Step 1.

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Add failing test — cycle terminates via visited set**

A → B → A edges (fakes). Assert `nodes_seen = 2` and no timeout/dump.

- [ ] **Step 6: Implement visited set; run — PASS.**

- [ ] **Step 7: Add failing test — class/FM check falls out of edge**

Fake detector `classify_edge` flags an edge to `ISU_AUTHORITY_CHECK` as a func check with object `E_INSTLN`. Assert a check of type `F`, object `E_INSTLN`, at the calling node's path.

- [ ] **Step 8: Implement edge classification; run — PASS.**

- [ ] **Step 9: Add failing tests — depth cap sets `max_depth_hit` + frontier; dynamic edge produces provisional node; `custom_only` scope stops at standard boundary with a frontier.**

- [ ] **Step 10: Implement guards/scope/provisional propagation; run — PASS.**

- [ ] **Step 11: Run ATC**

Run: `sap-adt run_atc_check` on `ZCL_AUTH_SCAN_ENGINE`. Expected: no priority-1/2 findings.

- [ ] **Step 12: Definition of done** — engine active, all unit tests green, ATC clean.

---

## Task 4: Entry resolver — integration test on a known tcode

**Files:** `ZCL_AUTH_SCAN_ENTRY_RESOLVER` implements `ZIF_AUTH_SCAN_ENTRY`.

Logic: read `TSTC` (`PGMNA`, `CINFO`) + `TSTCP` for parameter transactions. Dialog/report tcode → main program → its include list (`D010INC` / `RS_PROGRAM_INDEX`); OO transactions → class pool include. Raise `ZCX_AUTH_SCAN` (msg 001/002) if not found.

- [ ] **Step 1: Failing integration test — real tcode**

```abap
METHOD resolve_ucom_customer.
  DATA(lt) = mo_cut->resolve( '/UCOM/CUSTOMER' ).
  " entry program is /UCOM/RP_MAINTAIN_CUSTOMER (from TSTC)
  cl_abap_unit_assert=>assert_not_initial( lt ).
  cl_abap_unit_assert=>assert_true(
    xsdbool( line_exists( lt[ table_line = '/UCOM/RP_MAINTAIN_CUSTOMER' ] ) ) ).
ENDMETHOD.
```
(`/UCOM/CUSTOMER → /UCOM/RP_MAINTAIN_CUSTOMER` is verified live in the spec.)

- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement.** Also handle "transaction not found" test → expect `ZCX_AUTH_SCAN`.
- [ ] **Step 4: Run — PASS.** ATC clean. DoD: active + green.

---

## Task 5: Cross-reference edge provider — integration test on known edges

**Files:** `ZCL_AUTH_SCAN_XREF_EDGES` implements `ZIF_AUTH_SCAN_EDGE_PROVIDER`.

Logic: `SELECT otype, name FROM wbcrossgt WHERE include = iv_include`. Keep `OTYPE = 'ME'` (method calls) and function-module references; parse `NAME` of form `OBJECT\ME:METHOD` into `ty_object_ref` (split on `\` and `:`). Add `PERFORM` targets from `CROSS` (form references). Map `OTYPE` → `kind`: `ME` on an interface name → `intf`, on a class → `method`; FM → `func`; form → `perform`.

> **Verify live before relying on it:** the `ME`/`DA`/`TY` `OTYPE` values and the `OBJECT\ME:METHOD` `NAME` format are verified verbatim from the probe. The `CROSS` table's field/type names for `PERFORM` references (and the exact `OTYPE`/marker for function-module references in `WBCROSSGT`) were **not** probed verbatim — query the live `CROSS` schema and one known program's rows first (e.g. via `sap-adt run_query`) and confirm the field names before coding the SELECT, to avoid a stall.

- [ ] **Step 1: Failing integration test — real cross-references**

Assert against the verified live data for `/UCOM/RP_MAINTAIN_CUSTOMER`:

```abap
METHOD edges_of_maintain_customer.
  DATA(lt) = mo_cut->get_edges( '/UCOM/RP_MAINTAIN_CUSTOMER' ).
  " method-call edge to the factory (OTYPE 'ME')
  cl_abap_unit_assert=>assert_true( xsdbool( line_exists( lt[
      kind = zif_auth_scan_types=>gc_edge_kind-method
      target-object   = '/UCOM/CL_CUSTOMER_FACTORY'
      target-sub_name = 'GET_CUSTOMER_ACCESS' ] ) ) ).
ENDMETHOD.
```

- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement `NAME` parser + selects.** Add a parser unit test: `/UCOM/CL_CUSTOMER_FACTORY\ME:GET_CUSTOMER_ACCESS` → object/sub_name split; ignore `\DA:` data refs.
- [ ] **Step 4: Run — PASS.** ATC clean. DoD.

---

## Task 6: Object→include resolver — with interface dispatch

**Files:** `ZCL_AUTH_SCAN_INCL_RESOLVER` implements `ZIF_AUTH_SCAN_INCL_RESOLVER`.

Logic:
- Class method → include via `cl_oo_classname_service=>get_method_include( )`.
- **Interface method** (target object is an interface, e.g. `/UCOM/IF_CUSTOMER_ACCESS`) → find implementing classes via `SEOMETAREL` (`refclsname = interface`, `reltype` = implementation) → for each, resolve the method include; return all. Set `ev_unresolved` only if none found.
- FM → function group via `TFDIR-PNAME`/`FUNCNAME`, then the FM include (`L<fgrp>Uxx` / `RS_FUNCTIONMODULE_INSDER`-style mapping via `TFDIR`+`ENLFDIR`).
- Form (`PERFORM`) → the include is the edge source or a `CROSS`-referenced program; return that program.

- [ ] **Step 1: Failing integration test — class method include**

```abap
METHOD method_include_of_access. " CL_OO_CLASSNAME_SERVICE
  mo_cut->resolve( EXPORTING is_edge = edge_method(
       object = '/UCOM/CL_CUSTOMER_ACCESS' sub = 'CHECK_AUTHORIZATION' )
     IMPORTING et_includes = DATA(lt) ev_unresolved = DATA(lv) ).
  cl_abap_unit_assert=>assert_false( lv ).
  cl_abap_unit_assert=>assert_not_initial( lt ).
ENDMETHOD.
```

- [ ] **Step 2: Failing integration test — interface dispatch**

Edge to `/UCOM/IF_CUSTOMER_ACCESS~RELOAD_CUSTOMER` resolves to include(s) that include `/UCOM/CL_CUSTOMER_ACCESS`'s implementation (verified: it implements the interface).

- [ ] **Step 3: Failing integration test — FM include** (`ISU_AUTHORITY_CHECK` → its function group include).

- [ ] **Step 4: Run — FAIL. Implement. Run — PASS.** ATC clean. DoD.

---

## Task 7: Auth-API registry table + delivered content

**Files:** `ZAUTH_SCAN_API` (TABL, customizing/delivery class), + `set_source_from_file`/`update_customizing` for entries. Consider an SM30 maintenance view (later; not required for MVP).

Table fields: `API_KIND` (`F` FM / `K` class-method), `OBJ_NAME` (FM or class), `METH_NAME` (method; blank for FM), `OBJECT_ARG` (name of the argument carrying the auth object, e.g. `X_OBJECT`/`OBJECT`), `ACTIVE`, `DESCR`. Key: `API_KIND`, `OBJ_NAME`, `METH_NAME`.

- [ ] **Step 1: Create table via `create_object` type `TABL`.** Activate.
- [ ] **Step 2: Insert delivered rows** (via a small setup report or customizing update): `AUTHORITY_CHECK`(OBJECT_ARG=`OBJECT`), `AUTHORITY_CHECK_TCODE`(`TCODE`→special), `VIEW_AUTHORITY_CHECK`(`VIEW_ACTION`/`VIEW_NAME`→n/a, mark object-less), `ISU_AUTHORITY_CHECK`(`X_OBJECT`), `CL_ABAP_AUTHORITY_CHECK` methods (`K`, object arg = `object`). 
- [ ] **Step 3: DoD** — table active, delivered rows present (verify with a read test in Task 8).

---

## Task 8: Check detector — registry match + FM-arg extraction + SCAN

**Files:** `ZCL_AUTH_SCAN_DETECTOR` implements `ZIF_AUTH_SCAN_DETECTOR` + test include.

Logic:
- `classify_edge`: look up `is_edge-target` in `ZAUTH_SCAN_API`. If matched → build `ty_check` (type `F` or `K`); read the object argument at the call site: parse the source of `is_edge-source_include` for the call and extract the value passed to `OBJECT_ARG`. If literal/constant → resolve constant value → `auth_object`, `object_known = abap_true`; else `object_known = abap_false`.
- `scan_include`: `READ REPORT iv_include INTO lt_src`; `SCAN ABAP-SOURCE lt_src TOKENS INTO lt_tok STATEMENTS INTO lt_stmt`. For each statement whose first token = `AUTHORITY-CHECK`: extract `OBJECT` operand (next token; resolve literal/constant), `ID`/`FIELD` operands into `details`, and the statement line. Emit type `S`.

- [ ] **Step 1: Failing unit test — SCAN finds a classic statement**

Feed a fixture source array (a constant in the test) containing `AUTHORITY-CHECK OBJECT 'S_TCODE' ID 'TCD' FIELD 'SU01'.` via an injectable "source reader" seam (wrap `READ REPORT` behind a private method / injectable interface so the parser is unit-testable). Assert one check, type `S`, object `S_TCODE`, correct line.

- [ ] **Step 2: Run — FAIL. Implement SCAN parser. Run — PASS.**

- [ ] **Step 3: Failing integration test — classify `ISU_AUTHORITY_CHECK`**

Build an edge to `ISU_AUTHORITY_CHECK` with `source_include = /UCOM/CL_CUSTOMER_ACCESS`'s CHECK_AUTHORIZATION include. Assert: `ev_is_check = X`, type `F`, and `auth_object = 'E_INSTLN'` with `object_known = X` (constant `lc_object_e_instln VALUE 'E_INSTLN'` resolved). This is the live-validated case.

- [ ] **Step 4: Run — FAIL. Implement registry lookup + arg extraction + constant resolution. Run — PASS.** ATC clean. DoD.

---

## Task 9: Dynamic / BAdI expander

**Files:** `ZCL_AUTH_SCAN_EXPANDER` implements `ZIF_AUTH_SCAN_EXPANDER` + tests.

Logic:
- BAdI edge (classic: `CL_EXITHANDLER=>GET_INSTANCE`/`GET_INSTANCE_FOR_SUBSCREENS`; new: `GET BADI`/`CALL BADI`) → look up active implementations (classic: `SXC_EXIT`/`SXS_ATTR`/`V_EXT_IMP`; new BAdI: enhancement spot registry) → return implementing class method includes as **provisional** candidates.
- Dynamic `CALL FUNCTION lv_x` / `CALL METHOD ...->(lv_m)` → best-effort: if a naming pattern is discernible, return candidates; otherwise `ev_has_frontier = X` with reason.

- [ ] **Step 1: Failing test — unresolvable dynamic call yields frontier only** (unit, no candidates).
- [ ] **Step 2: Implement. PASS.**
- [ ] **Step 3a: Discovery — pick a stable BAdI fixture.** Unlike the `/UCOM/` chain, no BAdI was live-probed. First discover a stable, active BAdI implementation to assert against (query the enhancement registry, e.g. classic `SXC_EXIT`/`V_EXT_IMP` or a new-BAdI enhancement spot with an active implementation). Record its name + expected implementing class as the test fixture. Do **not** treat any BAdI name as a known value until discovered.
- [ ] **Step 3b: Failing integration test — the discovered BAdI resolves to ≥1 active implementation** (assert candidate returned + `is_provisional`/expander-provisional flag set).
- [ ] **Step 4: Implement BAdI registry lookup. PASS.** ATC clean. DoD.

---

## Task 10: Facade — wire concrete implementations, end-to-end

**Files:** `ZCL_AUTH_SCAN_FACADE` + integration test.

Logic: static `create( )` news up the concrete collaborators and injects them into `ZCL_AUTH_SCAN_ENGINE`. Public `run( iv_tcode, iv_max_depth = 100, iv_scope = into_standard )` delegates to the engine and returns `ty_result`.

> **This facade IS the shipped "callable API class"** the spec calls for — the report (Task 11) and any external/ATC/CI caller both go through `ZCL_AUTH_SCAN_FACADE=>create( )->run( )`. There is no separate API object.

- [ ] **Step 1: Failing end-to-end integration test — the live-validated case**

```abap
METHOD e2e_ucom_customer.
  DATA(ls) = zcl_auth_scan_facade=>create( )->run( iv_tcode = '/UCOM/CUSTOMER' ).
  " The buried ISU_AUTHORITY_CHECK on E_INSTLN must appear in the inventory.
  cl_abap_unit_assert=>assert_true( xsdbool( line_exists( ls-checks[
      check_type  = zif_auth_scan_types=>gc_check_type-func
      auth_object = 'E_INSTLN' ] ) ) ).
ENDMETHOD.
```

- [ ] **Step 2: Run — FAIL. Wire facade. Run — PASS.**

This test is the plan's acceptance criterion: it proves the tool recovers, from the transaction alone, the authorization check we found by hand.

- [ ] **Step 3: Performance sanity** — run against `/UCOM/CUSTOMER` with `into_standard`; log `nodes_seen` and runtime. If runtime is excessive, confirm the visited set and standard-boundary handling behave. DoD: active + green.

---

## Task 11: Report `Z_AUTH_SCAN` — selection screen + ALV

**Files:** `Z_AUTH_SCAN` (PROG).

Logic: selection screen — `p_tcode` (obligatory), `p_depth` (default 100), `p_scope` (radio: into-standard default / custom-only). Call facade. Render two `CL_SALV_TABLE` grids (or one with a tabstrip): the **inventory** (check type, auth object, object-known flag, include, unit, line, provisional, path) and the **frontier** (source include, kind, reason, path). Handle `ZCX_AUTH_SCAN` → message.

- [ ] **Step 1: Create report, implement selection screen + facade call + ALV.**
- [ ] **Step 2: Manual smoke via `sap-desktop`** — run `Z_AUTH_SCAN` for `/UCOM/CUSTOMER`, screenshot, confirm `E_INSTLN` row appears. (Report ALV logic isn't unit-tested; the facade test covers logic.)
- [ ] **Step 3: DoD** — report active; smoke screenshot captured.

---

## Task 12: abapGit roundtrip + PR

Now that the tool is validated in-system, bring the source into git for human review.

**Prerequisite (already satisfied):** the GitHub repo `Hochfrequenz/recursive_abap_auth_check_reflection` and the `feature/auth-check-scanner` branch already exist (created during planning). The local repo lives at the project root alongside `docs/`. No git plumbing setup remains — this task only wires abapGit on the SAP side to that existing repo.

- [ ] **Step 1: Register `ZAUTH_SCAN` as an online abapGit repo** pointing at this GitHub repo (one-time, GUI/`sap-desktop`), or if already registered, proceed.
- [ ] **Step 2: Push from SAP** (abapGit stage+commit) so SAP serializes all objects to `src/` (lowercase filenames). Do **not** hand-write XML.
- [ ] **Step 3: Pull/verify** the branch locally; confirm `src/` contains all objects listed in the structure table.
- [ ] **Step 4: Commit any repo-side docs, open a PR** from `feature/auth-check-scanner` → `main` with a description explaining the design, the live validation, and the acceptance test.
- [ ] **Step 5: DoD** — PR open, CI/lint (if any) green, source reviewable.

---

## Sequencing notes

- Tasks 1→2→3 first (types, interfaces, engine) so the core algorithm is locked with fakes before any DB work.
- Tasks 4, 5, 6, 9 (DB/repository collaborators) are independent of each other and can be parallelized across subagents; each has its own integration tests against stable objects.
- Task 7 precedes Task 8 (detector needs the registry table).
- Task 10 depends on 3–9; Task 11 on 10; Task 12 last.
- **Acceptance criterion for the whole tool:** the Task 10 end-to-end test recovering `E_INSTLN` from `/UCOM/CUSTOMER`.
