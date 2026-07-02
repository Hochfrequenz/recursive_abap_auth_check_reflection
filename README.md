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

## Development coordinates

Where this lives while it is being built (in-system first; abapGit later).

- **System:** HF S/4 Mandant 100.
- **Package:** `ZAUTH_SCAN` (transportable; software component HOME, transport layer ZS4U).
- **Transport request:** `S4UK903496` (workbench, modifiable — the project TR; never released without explicit permission).
- **Message class:** `ZAUTH_SCAN` (messages 001–004).
- **Object prefixes:** `ZCL_AUTH_SCAN_*` (classes), `ZIF_AUTH_SCAN_*` (interfaces), `ZCX_AUTH_SCAN` (exception), `Z_AUTH_SCAN` (report), `ZAUTH_SCAN_*` (DDIC / message class).
- **abapGit:** linking this repo to the package needs a valid GitHub PAT (the MCP env-var PAT is expired/absent) — supply one before the Task 12 roundtrip.

## Status

Early build. Foundation created (package, transport, message class); implementation follows the plan in `docs/superpowers/plans/`.
