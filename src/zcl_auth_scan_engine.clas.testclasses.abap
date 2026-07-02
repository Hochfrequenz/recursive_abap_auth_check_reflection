*----------------------------------------------------------------------*
* recursive_abap_auth_check_reflection
* https://github.com/Hochfrequenz/recursive_abap_auth_check_reflection
* SPDX-License-Identifier: MIT
*----------------------------------------------------------------------*
*"* ABAP Unit tests for ZCL_AUTH_SCAN_ENGINE — pure logic, fake collaborators.

CLASS ltd_entry DEFINITION.
  PUBLIC SECTION.
    INTERFACES zif_auth_scan_entry.
    DATA seeds TYPE zif_auth_scan_types=>includes.
ENDCLASS.
CLASS ltd_entry IMPLEMENTATION.
  METHOD zif_auth_scan_entry~resolve.
    includes = seeds.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_edges DEFINITION.
  PUBLIC SECTION.
    INTERFACES zif_auth_scan_edge_provider.
    TYPES: BEGIN OF row,
             from TYPE progname,
             edge TYPE zif_auth_scan_types=>edge,
           END OF row.
    DATA rows TYPE STANDARD TABLE OF row WITH EMPTY KEY.
    METHODS add
      IMPORTING from     TYPE progname
                object   TYPE string
                sub_name TYPE string             DEFAULT ''
                kind     TYPE zif_auth_scan_types=>edge_kind
                           DEFAULT zif_auth_scan_types=>edge_kinds-method.
ENDCLASS.
CLASS ltd_edges IMPLEMENTATION.
  METHOD add.
    APPEND VALUE #( from = from
                    edge = VALUE #( source_include = from
                                    kind           = kind
                                    target         = VALUE #( object   = object
                                                              sub_name = sub_name
                                                              raw      = object ) ) ) TO rows.
  ENDMETHOD.
  METHOD zif_auth_scan_edge_provider~get_edges.
    LOOP AT rows INTO DATA(r).
      IF r-from = include.
        APPEND r-edge TO edges.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_resolver DEFINITION.
  PUBLIC SECTION.
    INTERFACES zif_auth_scan_incl_resolver.
ENDCLASS.
CLASS ltd_resolver IMPLEMENTATION.
  METHOD zif_auth_scan_incl_resolver~resolve.
    IF edge-target-object = 'UNRESOLVED'.
      result-is_unresolved = abap_true.
    ELSE.
      result-includes = VALUE #( ( CONV progname( edge-target-object ) ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_expander DEFINITION.
  PUBLIC SECTION.
    INTERFACES zif_auth_scan_expander.
    DATA to_return TYPE zif_auth_scan_types=>expansion.
ENDCLASS.
CLASS ltd_expander IMPLEMENTATION.
  METHOD zif_auth_scan_expander~expand.
    result = to_return.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_detector DEFINITION.
  PUBLIC SECTION.
    INTERFACES zif_auth_scan_detector.
    TYPES: BEGIN OF srow,
             include TYPE progname,
             check   TYPE zif_auth_scan_types=>auth_check,
           END OF srow.
    DATA statements TYPE STANDARD TABLE OF srow WITH EMPTY KEY.
    DATA api_object TYPE string.
    DATA api_check  TYPE zif_auth_scan_types=>auth_check.
    METHODS add_statement
      IMPORTING include TYPE progname
                object  TYPE string.
ENDCLASS.
CLASS ltd_detector IMPLEMENTATION.
  METHOD add_statement.
    APPEND VALUE #( include = include
                    check   = VALUE #( type         = zif_auth_scan_types=>check_types-statement
                                       object       = object
                                       object_known = abap_true
                                       include      = include ) ) TO statements.
  ENDMETHOD.
  METHOD zif_auth_scan_detector~scan_include.
    LOOP AT statements INTO DATA(s).
      IF s-include = include.
        APPEND s-check TO checks.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_auth_scan_detector~classify_edge.
    IF api_object IS NOT INITIAL AND edge-target-object = api_object.
      result-is_check = abap_true.
      result-check    = api_check.
    ENDIF.
  ENDMETHOD.
ENDCLASS.


CLASS ltc_engine DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA entry    TYPE REF TO ltd_entry.
    DATA edges    TYPE REF TO ltd_edges.
    DATA resolver TYPE REF TO ltd_resolver.
    DATA expander TYPE REF TO ltd_expander.
    DATA detector TYPE REF TO ltd_detector.

    METHODS build RETURNING VALUE(engine) TYPE REF TO zcl_auth_scan_engine.

    METHODS one_node_one_statement FOR TESTING RAISING zcx_auth_scan.
    METHODS cycle_terminates       FOR TESTING RAISING zcx_auth_scan.
    METHODS fm_check_from_edge     FOR TESTING RAISING zcx_auth_scan.
    METHODS depth_cap              FOR TESTING RAISING zcx_auth_scan.
    METHODS graph_retention        FOR TESTING RAISING zcx_auth_scan.
    METHODS custom_only_boundary   FOR TESTING RAISING zcx_auth_scan.
ENDCLASS.

CLASS ltc_engine IMPLEMENTATION.

  METHOD build.
    entry    = NEW #( ).
    edges    = NEW #( ).
    resolver = NEW #( ).
    expander = NEW #( ).
    detector = NEW #( ).
    engine = NEW zcl_auth_scan_engine( entry         = entry
                                       edge_provider = edges
                                       resolver      = resolver
                                       expander      = expander
                                       detector      = detector ).
  ENDMETHOD.

  METHOD one_node_one_statement.
    DATA(engine) = build( ).
    entry->seeds = VALUE #( ( 'ZTEST_SEED' ) ).
    detector->add_statement( include = 'ZTEST_SEED' object = 'S_DEVELOP' ).

    DATA(res) = engine->run( transaction = 'ZT1' ).

    cl_abap_unit_assert=>assert_equals( act = lines( res-checks ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = res-checks[ 1 ]-object exp = 'S_DEVELOP' ).
    cl_abap_unit_assert=>assert_equals( act = res-nodes_seen exp = 1 ).
  ENDMETHOD.

  METHOD cycle_terminates.
    DATA(engine) = build( ).
    entry->seeds = VALUE #( ( 'A' ) ).
    edges->add( from = 'A' object = 'B' ).
    edges->add( from = 'B' object = 'A' ).

    DATA(res) = engine->run( transaction = 'ZT2' ).

    cl_abap_unit_assert=>assert_equals( act = res-nodes_seen exp = 2 ).
  ENDMETHOD.

  METHOD fm_check_from_edge.
    DATA(engine) = build( ).
    entry->seeds = VALUE #( ( 'ZSEED' ) ).
    edges->add( from = 'ZSEED' object = 'ISU_AUTHORITY_CHECK'
                kind = zif_auth_scan_types=>edge_kinds-function ).
    detector->api_object = 'ISU_AUTHORITY_CHECK'.
    detector->api_check  = VALUE #( type         = zif_auth_scan_types=>check_types-function_module
                                    object       = 'E_INSTLN'
                                    object_known = abap_true ).

    DATA(res) = engine->run( transaction = 'ZT3' ).

    cl_abap_unit_assert=>assert_true(
      xsdbool( line_exists( res-checks[ type   = zif_auth_scan_types=>check_types-function_module
                                        object = 'E_INSTLN' ] ) ) ).
  ENDMETHOD.

  METHOD depth_cap.
    DATA(engine) = build( ).
    entry->seeds = VALUE #( ( 'A' ) ).
    edges->add( from = 'A' object = 'B' ).

    DATA(res) = engine->run( transaction = 'ZT4' max_depth = 0 ).

    cl_abap_unit_assert=>assert_true( res-max_depth_hit ).
  ENDMETHOD.

  METHOD graph_retention.
    DATA(engine) = build( ).
    entry->seeds = VALUE #( ( 'A' ) ).
    edges->add( from = 'A' object = 'B' sub_name = 'M1' ).
    edges->add( from = 'B' object = 'C' sub_name = 'M2' ).

    DATA(res) = engine->run( transaction = 'ZT5' ).

    cl_abap_unit_assert=>assert_equals( act = lines( res-nodes ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = lines( res-graph_edges ) exp = 2 ).
    cl_abap_unit_assert=>assert_true(
      xsdbool( line_exists( res-graph_edges[ from_include = 'A' to_include = 'B' label = 'B=>M1' ] ) ) ).
  ENDMETHOD.

  METHOD custom_only_boundary.
    DATA(engine) = build( ).
    entry->seeds = VALUE #( ( 'ZSEED' ) ).
    edges->add( from = 'ZSEED' object = 'CL_STANDARD' sub_name = 'DO' ).

    DATA(res) = engine->run( transaction = 'ZT6'
                             scope       = zif_auth_scan_types=>scopes-custom_only ).

    cl_abap_unit_assert=>assert_false(
      xsdbool( line_exists( res-nodes[ include = 'CL_STANDARD' ] ) ) ).
    cl_abap_unit_assert=>assert_true(
      xsdbool( line_exists( res-frontier[ source_include = 'ZSEED' ] ) ) ).
    cl_abap_unit_assert=>assert_true(
      xsdbool( line_exists( res-graph_edges[ to_include = 'CL_STANDARD' ] ) ) ).
  ENDMETHOD.

ENDCLASS.