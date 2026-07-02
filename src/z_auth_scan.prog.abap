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

INITIALIZATION.
  c_tcode = 'Transaction code'.
  c_depth = 'Max. recursion depth'.
  c_std   = 'Descend into SAP standard'.
  c_cust  = 'Custom code only'.

CLASS lcl_app DEFINITION CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS main.
    METHODS on_added_function FOR EVENT added_function OF cl_salv_events_table
      IMPORTING e_salv_function.
  PRIVATE SECTION.
    DATA facade TYPE REF TO zcl_auth_scan_facade.
    DATA result TYPE zif_auth_scan_types=>result.
    METHODS open_graph.
    METHODS set_headers
      IMPORTING columns TYPE REF TO cl_salv_columns.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.

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

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(alv)
                                CHANGING  t_table      = result-checks ).

        alv->get_functions( )->set_all( ).
        alv->get_functions( )->add_function(
          name     = 'KROKI'
          text     = 'Graph (kroki.io)'
          tooltip  = 'Render the reachable call graph on kroki.io'
          position = if_salv_c_function_position=>right_of_salv_functions ).
        SET HANDLER on_added_function FOR alv->get_event( ).

        " group the inventory by authorization object (Berechtigungsobjekt)
        DATA(sorts) = alv->get_sorts( ).
        sorts->add_sort( columnname = 'OBJECT'  subtotal = abap_true ).
        sorts->add_sort( columnname = 'TYPE' ).
        sorts->add_sort( columnname = 'INCLUDE' ).

        DATA(columns) = alv->get_columns( ).
        columns->set_optimize( ).
        set_headers( columns ).

        alv->get_display_settings( )->set_list_header(
          |Authorization checks reachable from { p_tcode }| ).
        alv->display( ).

      CATCH cx_salv_msg cx_salv_not_found cx_salv_existing cx_salv_data_error
            cx_salv_wrong_call INTO DATA(salv_error).
        MESSAGE salv_error->get_text( ) TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD on_added_function.
    IF e_salv_function = 'KROKI'.
      open_graph( ).
    ENDIF.
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
      ( field = 'TYPE'           short = 'Type'    med = 'Check type'   long = 'Check type (S/K/F)' )
      ( field = 'OBJECT'         short = 'Object'  med = 'Auth. object' long = 'Authorization object' )
      ( field = 'OBJECT_KNOWN'   short = 'Known'   med = 'Object known' long = 'Object statically known' )
      ( field = 'DETAILS'        short = 'Detail'  med = 'Detail'       long = 'Detail (ID/FIELD or API)' )
      ( field = 'INCLUDE'        short = 'Include' med = 'Include'      long = 'Include' )
      ( field = 'UNIT'           short = 'Unit'    med = 'Unit'         long = 'Method / form' )
      ( field = 'LINE'           short = 'Line'    med = 'Line'         long = 'Source line' )
      ( field = 'PATH'           short = 'Path'    med = 'Call path'    long = 'Call path from transaction' )
      ( field = 'IS_PROVISIONAL' short = 'Prov.'   med = 'Provisional'  long = 'Provisional (heuristic)' ) ).

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

START-OF-SELECTION.
  NEW lcl_app( )->main( ).
