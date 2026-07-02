CLASS zcl_auth_scan_expander DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_auth_scan_expander.
ENDCLASS.


CLASS zcl_auth_scan_expander IMPLEMENTATION.

  METHOD zif_auth_scan_expander~expand.
    " This version does not statically expand dynamic/BAdI edges (heuristic
    " expansion is a later enhancement); the edge is reported as a frontier.
    result-has_frontier = abap_true.
    result-frontier = VALUE #( source_include = edge-source_include
                               kind            = edge-kind
                               reason          = |unexpanded dynamic/BAdI edge { edge-target-object }|
                               raw             = edge-target-raw ).
  ENDMETHOD.

ENDCLASS.
