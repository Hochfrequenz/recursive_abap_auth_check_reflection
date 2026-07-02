INTERFACE zif_auth_scan_detector
  PUBLIC.

  "! Classify an edge: is its target a known authorization API? If so, the
  "! returned check carries the authorization object filled from the call
  "! arguments when it is statically recoverable.
  "! @parameter edge   | the edge to classify
  "! @parameter result | whether it is a check, and the check itself
  METHODS classify_edge
    IMPORTING edge          TYPE zif_auth_scan_types=>edge
    RETURNING VALUE(result) TYPE zif_auth_scan_types=>classification.

  "! Scan one include for classic AUTHORITY-CHECK statements.
  "! @parameter include | the include to scan
  "! @parameter checks  | detected statement checks
  METHODS scan_include
    IMPORTING include       TYPE progname
    RETURNING VALUE(checks) TYPE zif_auth_scan_types=>auth_checks.

ENDINTERFACE.
