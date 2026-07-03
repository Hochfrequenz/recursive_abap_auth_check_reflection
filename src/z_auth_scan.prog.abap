*----------------------------------------------------------------------*
* recursive_abap_auth_check_reflection
* https://github.com/Hochfrequenz/recursive_abap_auth_check_reflection
* SPDX-License-Identifier: MIT
*----------------------------------------------------------------------*
*& Report z_auth_scan
*& Recursive authorization-check scanner: given a transaction, walk the
*& reachable call graph and list every authorization check found in it.
*----------------------------------------------------------------------*
REPORT z_auth_scan.

SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN COMMENT 1(31) c_tcode FOR FIELD p_tcode.
PARAMETERS p_tcode TYPE tcode OBLIGATORY.
SELECTION-SCREEN END OF LINE.

SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN COMMENT 1(31) c_depth FOR FIELD p_depth.
PARAMETERS p_depth TYPE i DEFAULT 100.
SELECTION-SCREEN END OF LINE.

SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_std RADIOBUTTON GROUP scp DEFAULT 'X'.
SELECTION-SCREEN COMMENT 3(40) c_std FOR FIELD p_std.
SELECTION-SCREEN END OF LINE.

SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_cust RADIOBUTTON GROUP scp.
SELECTION-SCREEN COMMENT 3(40) c_cust FOR FIELD p_cust.
SELECTION-SCREEN END OF LINE.

SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_dot AS CHECKBOX.
SELECTION-SCREEN COMMENT 3(40) c_dot FOR FIELD p_dot.
SELECTION-SCREEN END OF LINE.


CLASS lcl_app DEFINITION CREATE PUBLIC.
  PUBLIC SECTION.
    "! F4 value help: transactions from TSTC (with description).
    CLASS-METHODS value_help.
    METHODS main.

  PRIVATE SECTION.
    "! Flat display row (CHAR fields — ALV cannot sort/subtotal STRING columns).
    TYPES: BEGIN OF display_row,
             auth_object  TYPE c LENGTH 30,
             activity     TYPE c LENGTH 60,
             check_type   TYPE c LENGTH 20,
             object_known TYPE abap_bool,
             include      TYPE progname,
             unit         TYPE c LENGTH 61,
             line         TYPE i,
             call_path    TYPE c LENGTH 255,
             provisional  TYPE abap_bool,
           END OF display_row,
           display_tab TYPE STANDARD TABLE OF display_row WITH EMPTY KEY.

    DATA facade TYPE REF TO zcl_auth_scan_facade.
    DATA result TYPE zif_auth_scan_types=>result.
    DATA rows   TYPE display_tab.

    METHODS build_rows.
    METHODS open_graph.
    METHODS set_headers
      IMPORTING columns TYPE REF TO cl_salv_columns.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.

  METHOD value_help.
    TYPES: BEGIN OF tcode_row,
             tcode TYPE tstc-tcode,
             ttext TYPE tstct-ttext,
           END OF tcode_row.
    DATA transactions TYPE STANDARD TABLE OF tcode_row.

    SELECT tstc~tcode, tstct~ttext
      FROM tstc
      LEFT OUTER JOIN tstct ON tstct~tcode = tstc~tcode
                           AND tstct~sprsl = @sy-langu
      ORDER BY tstc~tcode
      INTO CORRESPONDING FIELDS OF TABLE @transactions.

    CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
      EXPORTING
        retfield        = 'TCODE'
        dynpprog        = sy-repid
        dynpnr          = sy-dynnr
        dynprofield     = 'P_TCODE'
        value_org       = 'S'
      TABLES
        value_tab       = transactions
      EXCEPTIONS
        parameter_error = 1
        no_values_found = 2
        OTHERS          = 3.
  ENDMETHOD.

  METHOD main.
    DATA(scope) = COND zif_auth_scan_types=>scope(
      WHEN p_cust = abap_true THEN zif_auth_scan_types=>scopes-custom_only
      ELSE                         zif_auth_scan_types=>scopes-into_standard ).

    facade = zcl_auth_scan_facade=>create( ).

    TRY.
        result = facade->run( transaction = p_tcode
                              max_depth   = p_depth
                              scope       = scope ).
      CATCH zcx_auth_scan INTO DATA(error).
        MESSAGE error->get_text( ) TYPE 'E'.
        RETURN.
    ENDTRY.

    IF result-checks IS INITIAL.
      MESSAGE |No authorization checks reachable from { p_tcode } | &&
              |({ result-nodes_seen } units scanned).| TYPE 'I'.
      RETURN.
    ENDIF.

    IF p_dot = abap_true.
      open_graph( ).
      RETURN.
    ENDIF.

    build_rows( ).

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(alv)
                                CHANGING  t_table      = rows ).

        alv->get_functions( )->set_all( ).

        DATA(columns) = alv->get_columns( ).
        columns->set_optimize( ).
        set_headers( columns ).

        " group by authorization object (Berechtigungsobjekt)
        DATA(sorts) = alv->get_sorts( ).
        sorts->add_sort( columnname = 'AUTH_OBJECT' subtotal = abap_true ).
        sorts->add_sort( columnname = 'CHECK_TYPE' ).

        DATA(display) = alv->get_display_settings( ).
        display->set_striped_pattern( abap_true ).
        display->set_list_header( |Authorization checks reachable from { p_tcode }| ).

        alv->display( ).

      CATCH cx_salv_msg cx_salv_not_found cx_salv_existing cx_salv_data_error
            cx_salv_wrong_call INTO DATA(salv_error).
        MESSAGE salv_error->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD build_rows.
    LOOP AT result-checks INTO DATA(check).
      APPEND VALUE #(
        auth_object  = check-object
        activity     = check-details
        check_type   = SWITCH #( check-type
                         WHEN zif_auth_scan_types=>check_types-statement       THEN 'AUTHORITY-CHECK'
                         WHEN zif_auth_scan_types=>check_types-function_module THEN 'Function module'
                         WHEN zif_auth_scan_types=>check_types-class_based      THEN 'Class-based'
                         ELSE check-type )
        object_known = check-object_known
        include      = check-include
        unit         = check-unit
        line         = check-line
        call_path    = check-path
        provisional  = check-is_provisional ) TO rows.
    ENDLOOP.
  ENDMETHOD.

  METHOD open_graph.
    DATA(dot)    = facade->to_dot( result ).
    DATA(url)    = zcl_auth_scan_dot=>kroki_url( dot ).
    DATA(source) = dot.
    REPLACE ALL OCCURRENCES OF `&` IN source WITH `&amp;`.
    REPLACE ALL OCCURRENCES OF `<` IN source WITH `&lt;`.
    REPLACE ALL OCCURRENCES OF `>` IN source WITH `&gt;`.
    DATA(html) =
         |<html><body style="font-family:sans-serif">|
      && |<h3>Reachable call graph for { p_tcode }</h3>|
      && |<p><a href="{ url }" target="_blank">&#9654; Render this graph on kroki.io</a></p>|
      && |<pre>{ source }</pre>|
      && |<hr><p style="color:#888888">recursive_abap_auth_check_reflection &middot; |
      && |<a href="https://github.com/Hochfrequenz/recursive_abap_auth_check_reflection" target="_blank">GitHub</a>|
      && | &middot; MIT License</p></body></html>|.
    cl_abap_browser=>show_html( html_string = html ).
  ENDMETHOD.

  METHOD set_headers.
    TYPES: BEGIN OF header,
             field TYPE lvc_fname,
             short TYPE scrtext_s,
             med   TYPE scrtext_m,
             long  TYPE scrtext_l,
           END OF header,
           header_tab TYPE STANDARD TABLE OF header WITH EMPTY KEY.
    DATA(headers) = VALUE header_tab(
      ( field = 'AUTH_OBJECT'  short = 'Object'   med = 'Auth. object'  long = 'Authorization object' )
      ( field = 'ACTIVITY'     short = 'Activity' med = 'Activity'      long = 'Activity (ID/FIELD values)' )
      ( field = 'CHECK_TYPE'   short = 'Type'     med = 'Check type'    long = 'Check type' )
      ( field = 'OBJECT_KNOWN' short = 'Known'    med = 'Object known'  long = 'Object statically known' )
      ( field = 'INCLUDE'      short = 'Include'  med = 'Include'       long = 'Include' )
      ( field = 'UNIT'         short = 'Unit'     med = 'Unit'          long = 'Method / form' )
      ( field = 'LINE'         short = 'Line'     med = 'Line'          long = 'Source line' )
      ( field = 'CALL_PATH'    short = 'Path'     med = 'Call path'     long = 'Call path from transaction' )
      ( field = 'PROVISIONAL'  short = 'Prov.'    med = 'Provisional'   long = 'Provisional (heuristic)' ) ).

    LOOP AT headers INTO DATA(entry).
      TRY.
          DATA(column) = columns->get_column( entry-field ).
          column->set_short_text( entry-short ).
          column->set_medium_text( entry-med ).
          column->set_long_text( entry-long ).
        CATCH cx_salv_not_found.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_tcode.
  lcl_app=>value_help( ).

INITIALIZATION.
  c_tcode = 'Transaction code'.
  c_depth = 'Max. recursion depth'.
  c_std   = 'Descend into SAP standard'.
  c_cust  = 'Custom code only'.
  c_dot   = 'Show call graph (DOT / kroki.io)'.

START-OF-SELECTION.
  NEW lcl_app( )->main( ).
