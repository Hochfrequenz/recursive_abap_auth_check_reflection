INTERFACE zif_auth_scan_incl_resolver
  PUBLIC.

  "! Resolve an edge target to the include(s) that implement it.
  "! Interface-method targets expand to every implementing class.
  "! @parameter is_edge       | the edge whose target is resolved
  "! @parameter et_includes   | implementing include(s)
  "! @parameter ev_unresolved | set when no include could be determined
  METHODS resolve
    IMPORTING is_edge       TYPE zif_auth_scan_types=>ty_edge
    EXPORTING et_includes   TYPE zif_auth_scan_types=>ty_includes
              ev_unresolved TYPE abap_bool.

ENDINTERFACE.
