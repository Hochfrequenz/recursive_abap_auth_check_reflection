*----------------------------------------------------------------------*
* recursive_abap_auth_check_reflection
* https://github.com/Hochfrequenz/recursive_abap_auth_check_reflection
* SPDX-License-Identifier: MIT
*----------------------------------------------------------------------*
INTERFACE zif_auth_scan_edge_provider
  PUBLIC.

  "! All outgoing call edges from one include (method / function-module / PERFORM).
  "! @parameter include | the using include
  "! @parameter edges   | outgoing call edges
  METHODS get_edges
    IMPORTING include      TYPE progname
    RETURNING VALUE(edges) TYPE zif_auth_scan_types=>edges.

ENDINTERFACE.