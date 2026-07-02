INTERFACE zif_auth_scan_expander
  PUBLIC.

  "! Expand a dynamic/BAdI edge to provisional candidate includes; anything
  "! still unresolved is returned as a frontier record.
  "! @parameter edge   | the dynamic/BAdI edge
  "! @parameter result | provisional candidate include(s) and optional frontier
  METHODS expand
    IMPORTING edge          TYPE zif_auth_scan_types=>edge
    RETURNING VALUE(result) TYPE zif_auth_scan_types=>expansion.

ENDINTERFACE.
