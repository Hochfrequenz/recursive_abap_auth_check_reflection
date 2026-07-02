INTERFACE zif_auth_scan_detector
  PUBLIC.

  "! Is this edge target a known authorization API? If so, return the check,
  "! with the authorization object filled from the call arguments when it is
  "! statically recoverable.
  "! @parameter is_edge     | the edge to classify
  "! @parameter es_check    | the check (valid when ev_is_check)
  "! @parameter ev_is_check | set when the target is a known auth API
  METHODS classify_edge
    IMPORTING is_edge     TYPE zif_auth_scan_types=>ty_edge
    EXPORTING es_check    TYPE zif_auth_scan_types=>ty_check
              ev_is_check TYPE abap_bool.

  "! Scan one include for classic AUTHORITY-CHECK statements.
  "! @parameter iv_include | the include to scan
  "! @parameter rt_checks  | detected statement checks
  METHODS scan_include
    IMPORTING iv_include       TYPE progname
    RETURNING VALUE(rt_checks) TYPE zif_auth_scan_types=>ty_checks.

ENDINTERFACE.
