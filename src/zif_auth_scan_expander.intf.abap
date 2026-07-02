INTERFACE zif_auth_scan_expander
  PUBLIC.

  "! Expand a dynamic/BAdI edge to provisional candidate includes; anything
  "! still unresolved is returned as a frontier record.
  "! @parameter is_edge         | the dynamic/BAdI edge
  "! @parameter et_includes     | provisional candidate include(s)
  "! @parameter es_frontier     | frontier record (valid when ev_has_frontier)
  "! @parameter ev_has_frontier | set when the edge stays (partly) unresolved
  METHODS expand
    IMPORTING is_edge         TYPE zif_auth_scan_types=>ty_edge
    EXPORTING et_includes     TYPE zif_auth_scan_types=>ty_includes
              es_frontier     TYPE zif_auth_scan_types=>ty_frontier
              ev_has_frontier TYPE abap_bool.

ENDINTERFACE.
