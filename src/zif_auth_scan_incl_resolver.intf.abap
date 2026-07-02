*----------------------------------------------------------------------*
* recursive_abap_auth_check_reflection
* https://github.com/Hochfrequenz/recursive_abap_auth_check_reflection
* SPDX-License-Identifier: MIT
*----------------------------------------------------------------------*
INTERFACE zif_auth_scan_incl_resolver
  PUBLIC.

  "! Resolve an edge target to the include(s) that implement it.
  "! Interface-method targets expand to every implementing class.
  "! @parameter edge   | the edge whose target is resolved
  "! @parameter result | implementing include(s), and whether nothing was found
  METHODS resolve
    IMPORTING edge          TYPE zif_auth_scan_types=>edge
    RETURNING VALUE(result) TYPE zif_auth_scan_types=>resolution.

ENDINTERFACE.