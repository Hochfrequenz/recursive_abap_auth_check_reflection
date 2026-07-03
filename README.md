# recursive_abap_auth_check_reflection
<!-- 1 line per sentence -->

Static analyzer for SAP ABAP: given a transaction code, it recursively computes the reachable call graph and produces a **complete inventory of authorization checks** buried anywhere in the reached code - **without** running the transaction.

## Why

Users are often authorized to *start* a transaction, but the authorization checks that actually matter live deep inside the invoked program logic (nested classes, function modules, form routines).
Exercising every path at runtime is infeasible; this tool finds the checks statically.

## What it detects

- Classic `AUTHORITY-CHECK OBJECT '...'` statements
- Class-based checks (`CL_ABAP_AUTHORITY_CHECK` and similar S/4 auth APIs)
- Authorization function modules (`AUTHORITY_CHECK`, `AUTHORITY_CHECK_TCODE`, `VIEW_AUTHORITY_CHECK`, other `AUTHORITY_CHECK*` wrappers)

## How it works (in brief)

An in-system ABAP analyzer BFS-walks the call graph from the transaction entry point, using SAP's cross-reference index (`WBCROSSGT`, `CROSS`) as the edge-provider.
Dynamic/BAdI edges are resolved best-effort (and tagged provisional); anything unresolved is reported as a **frontier** blind spot.
This report depends only on standard, always-present SAP infrastructure/coding and has no dependencies on customer or other Z-code.

## How it works — and how that differs from SUIM

```mermaid
flowchart TB
  subgraph THIS["This tool — deep, code-level reachability"]
    direction TB
    T["Transaction code"] --> E["Entry resolver<br/>TSTC → program + includes"]
    E --> B{"BFS over the<br/>reachable call graph"}
    B -->|"WBCROSSGT method calls<br/>CROSS function-module calls"| R["Resolve targets → method/FM includes<br/>(interface dispatch via SEOMETAREL)"]
    R --> B
    B --> D["Detector: SCAN each reached unit"]
    D --> C1["AUTHORITY-CHECK statements<br/>ID/FIELD resolved (e.g. ACTVT=03)"]
    D --> C2["Auth function modules<br/>object arg resolved (e.g. E_INSTLN)"]
    D --> C3["Class-based checks"]
    C1 --> INV["Complete inventory<br/>+ Graphviz DOT / kroki.io"]
    C2 --> INV
    C3 --> INV
    B -. "unresolved dynamic / BAdI" .-> F["Frontier<br/>(documented blind spots)"]
  end

  subgraph SUIM["SUIM / SU24 — transaction-start level only"]
    direction TB
    T2["Transaction code"] --> S1["Start authorization: S_TCODE"]
    T2 --> S2["SU24 / USOBT<br/>maintained check-indicator proposals"]
    S1 --> OUT["Authorizations to *start* the txn<br/>NOT the checks nested in the code"]
    S2 --> OUT
  end
```

## Compared to SUIM

SUIM (and the underlying SU24 / USOBT check indicators) answer *"which authorizations guard **starting** this transaction"* — essentially `S_TCODE` plus the maintained check-indicator proposals.
They do **not** follow the transaction's call graph into the code.
So an `AUTHORITY-CHECK` buried in a private method several calls deep — e.g. `ISU_AUTHORITY_CHECK` on `E_INSTLN`, reached from `/UCOM/CUSTOMER` via a factory, an interface and a private method — is invisible to SUIM.

This tool is complementary: it statically walks the reachable code and reports the *actual* checks in it — the authorization object, the `ID`/`FIELD` values, and the call path that reaches them — including checks SU24 never captured.

## Running it

Start transaction **`ZAUTH_SCAN`** (or run report `Z_AUTH_SCAN` via `SA38`).

On the selection screen:

- **Transaction code** — the transaction to analyze (F4 help lists all transactions).
- **Max. recursion depth** — how deep to follow the call graph (default 100).
- **Descend into SAP standard** / **Custom code only** — scope of the walk.
- **Show call graph (DOT / kroki.io)** — render the reachable graph instead of the list.

The result is an ALV grouped by authorization object.
Alongside the raw `ID`/`FIELD` values, a **Description** column renders each check in plain language (e.g. `B_EMMA_CAS` + `ACTVT=03` → "Case Authorization — Display"), resolving the authorization-object and activity texts in the logon language (English fallback).

## Development coordinates

Where this lives while it is being built (in-system first; abapGit later).

- **System:** HF S/4 Mandant 100.
- **Package:** `ZAUTH_SCAN` (transportable; software component HOME, transport layer ZS4U).
- **Transport request:** `S4UK903496` (workbench, modifiable — the project TR; never released without explicit permission).
- **Message class:** `ZAUTH_SCAN` (messages 001–004).
- **Object prefixes:** `ZCL_AUTH_SCAN_*` (classes), `ZIF_AUTH_SCAN_*` (interfaces), `ZCX_AUTH_SCAN` (exception), `Z_AUTH_SCAN` (report), `ZAUTH_SCAN` (transaction), `ZAUTH_SCAN_*` (DDIC / message class).
- **abapGit:** linking this repo to the package needs a valid GitHub PAT (the MCP env-var PAT is expired/absent) — supply one before the Task 12 roundtrip.
