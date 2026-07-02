CLASS zcl_auth_scan_incl_resolver DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_auth_scan_incl_resolver.

  PRIVATE SECTION.
    CONSTANTS interface_type TYPE seoclstype VALUE '1'.
    CONSTANTS implements_rel TYPE seometarel-reltype VALUE '1'.

    "! Method-implementation include for a class + component, or empty if none.
    METHODS method_include
      IMPORTING class         TYPE seoclsname
                cpdname       TYPE seocpdname
      RETURNING VALUE(result) TYPE progname.
ENDCLASS.


CLASS zcl_auth_scan_incl_resolver IMPLEMENTATION.

  METHOD zif_auth_scan_incl_resolver~resolve.
    " Function modules are treated as graph leaves: the auth-relevant ones are
    " detected at the call site; descending into every FM body would explode
    " the graph. (Opt-in FM descent is a later enhancement.)
    IF edge-kind = zif_auth_scan_types=>edge_kinds-function.
      RETURN.
    ENDIF.

    DATA(class_name) = CONV seoclsname( to_upper( edge-target-object ) ).
    SELECT SINGLE clstype FROM seoclass WHERE clsname = @class_name INTO @DATA(clstype).

    IF sy-subrc = 0 AND clstype = interface_type.
      " interface method -> every implementing class's method include
      SELECT clsname FROM seometarel
        WHERE refclsname = @class_name
          AND reltype    = @implements_rel
          AND version    = 1
        INTO TABLE @DATA(implementations).
      LOOP AT implementations INTO DATA(implementation).
        DATA(interface_include) = method_include(
          class   = implementation-clsname
          cpdname = CONV #( to_upper( |{ edge-target-object }~{ edge-target-sub_name }| ) ) ).
        IF interface_include IS NOT INITIAL
        AND NOT line_exists( result-includes[ table_line = interface_include ] ).
          APPEND interface_include TO result-includes.
        ENDIF.
      ENDLOOP.
    ELSE.
      " direct class method
      DATA(class_include) = method_include( class   = class_name
                                            cpdname = CONV #( to_upper( edge-target-sub_name ) ) ).
      IF class_include IS NOT INITIAL.
        APPEND class_include TO result-includes.
      ENDIF.
    ENDIF.

    IF result-includes IS INITIAL.
      result-is_unresolved = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD method_include.
    " get_method_include raises CLASSIC exceptions (not class-based), so it must
    " be called with an EXCEPTIONS clause rather than TRY/CATCH.
    CALL METHOD cl_oo_classname_service=>get_method_include
      EXPORTING mtdkey              = VALUE seocpdkey( clsname = class cpdname = cpdname )
      RECEIVING result              = result
      EXCEPTIONS class_not_existing  = 1
                 method_not_existing = 2
                 OTHERS              = 3.
    IF sy-subrc <> 0.
      CLEAR result.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
