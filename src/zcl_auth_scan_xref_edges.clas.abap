CLASS zcl_auth_scan_xref_edges DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_auth_scan_edge_provider.

  PRIVATE SECTION.
    "! Parse a WBCROSSGT method reference `OBJECT\ME:METHOD` into object + method.
    METHODS parse_method_ref
      IMPORTING name          TYPE clike
      RETURNING VALUE(target)  TYPE zif_auth_scan_types=>object_ref.
ENDCLASS.


CLASS zcl_auth_scan_xref_edges IMPLEMENTATION.

  METHOD zif_auth_scan_edge_provider~get_edges.
    " method calls (and interface-method calls) — WBCROSSGT, OTYPE 'ME'
    SELECT name FROM wbcrossgt
      WHERE include = @include AND otype = 'ME'
      INTO TABLE @DATA(method_refs).
    LOOP AT method_refs INTO DATA(method_ref).
      APPEND VALUE #( source_include = include
                      kind           = zif_auth_scan_types=>edge_kinds-method
                      target         = parse_method_ref( method_ref-name ) ) TO edges.
    ENDLOOP.

    " function-module calls — classic CROSS index, TYPE 'F'
    SELECT name FROM cross
      WHERE include = @include AND type = 'F'
      INTO TABLE @DATA(function_refs).
    LOOP AT function_refs INTO DATA(function_ref).
      APPEND VALUE #( source_include = include
                      kind           = zif_auth_scan_types=>edge_kinds-function
                      target         = VALUE #( otype  = 'FUNC'
                                                object = CONV string( function_ref-name )
                                                raw    = CONV string( function_ref-name ) ) ) TO edges.
    ENDLOOP.
  ENDMETHOD.

  METHOD parse_method_ref.
    DATA(raw) = CONV string( name ).
    target = VALUE #( otype = 'ME' raw = raw ).
    SPLIT raw AT '\' INTO DATA(object_part) DATA(rest).
    target-object = object_part.
    IF rest CS ':'.
      SPLIT rest AT ':' INTO DATA(tag) DATA(method).
      target-sub_name = method.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
