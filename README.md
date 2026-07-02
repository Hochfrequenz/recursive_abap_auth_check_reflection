# recursive_abap_auth_check_reflection

Static analyzer for SAP ABAP: given a transaction code, it recursively computes
the reachable call graph and produces a **complete inventory of authorization
checks** buried anywhere in the reached code — without running the transaction.

## Why

Users are often authorized to *start* a transaction, but the authorization
checks that actually matter live deep inside the invoked program logic (nested
classes, function modules, form routines). Exercising every path at runtime is
infeasible; this tool finds the checks statically.

## What it detects

- Classic `AUTHORITY-CHECK OBJECT '...'` statements
- Class-based checks (`CL_ABAP_AUTHORITY_CHECK` and similar S/4 auth APIs)
- Authorization function modules (`AUTHORITY_CHECK`, `AUTHORITY_CHECK_TCODE`,
  `VIEW_AUTHORITY_CHECK`, other `AUTHORITY_CHECK*` wrappers)

## How it works (in brief)

An in-system ABAP analyzer BFS-walks the call graph from the transaction entry
point, using SAP's cross-reference index (`WBCROSSGT`, `CROSS`) as the
edge-provider. Dynamic/BAdI edges are resolved best-effort (and tagged
provisional); anything unresolved is reported as a **frontier** blind spot.
Depends only on standard, always-present SAP infrastructure — no dependency on
customer code.

See [`docs/superpowers/specs/`](docs/superpowers/specs/) for the full design.

## Status

Early design. Development happens in-system first; distribution via abapGit
follows once the tool is validated.
