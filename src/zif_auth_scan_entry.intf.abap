*----------------------------------------------------------------------*
* recursive_abap_auth_check_reflection
* https://github.com/Hochfrequenz/recursive_abap_auth_check_reflection
* SPDX-License-Identifier: MIT
*----------------------------------------------------------------------*
INTERFACE zif_auth_scan_entry
  PUBLIC.

  "! Resolve a transaction code to its entry-point include(s).
  "! @parameter transaction | transaction code
  "! @parameter includes    | entry-point program include(s)
  "! @raising   zcx_auth_scan | transaction not found / no entry point
  METHODS resolve
    IMPORTING transaction     TYPE tcode
    RETURNING VALUE(includes) TYPE zif_auth_scan_types=>includes
    RAISING   zcx_auth_scan.

ENDINTERFACE.