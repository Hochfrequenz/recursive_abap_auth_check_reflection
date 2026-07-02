INTERFACE zif_auth_scan_entry
  PUBLIC.

  "! Resolve a transaction code to its entry-point include(s).
  "! @parameter iv_tcode    | transaction code
  "! @parameter rt_includes | entry-point program include(s)
  "! @raising   zcx_auth_scan | transaction not found / no entry point
  METHODS resolve
    IMPORTING iv_tcode           TYPE tcode
    RETURNING VALUE(rt_includes) TYPE zif_auth_scan_types=>ty_includes
    RAISING   zcx_auth_scan.

ENDINTERFACE.
