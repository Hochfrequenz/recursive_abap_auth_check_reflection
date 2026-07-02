INTERFACE zif_auth_scan_edge_provider
  PUBLIC.

  "! All outgoing call edges from one include (method / function-module / PERFORM).
  "! @parameter iv_include | the using include
  "! @parameter rt_edges   | outgoing call edges
  METHODS get_edges
    IMPORTING iv_include      TYPE progname
    RETURNING VALUE(rt_edges) TYPE zif_auth_scan_types=>ty_edges.

ENDINTERFACE.
