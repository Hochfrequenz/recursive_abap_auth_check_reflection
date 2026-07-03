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
             description  TYPE c LENGTH 120,
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

    "! One resolved short text keyed by object / activity code.
    TYPES: BEGIN OF text_entry,
             key  TYPE string,
             text TYPE string,
           END OF text_entry,
           text_map TYPE HASHED TABLE OF text_entry WITH UNIQUE KEY key.

    DATA facade TYPE REF TO zcl_auth_scan_facade.
    DATA result TYPE zif_auth_scan_types=>result.
    DATA rows   TYPE display_tab.

    "! Authorization object texts (TOBJT), keyed by object name.
    DATA object_texts   TYPE text_map.
    "! Activity texts (TACTT), keyed by ACTVT code.
    DATA activity_texts TYPE text_map.

    METHODS build_rows.
    METHODS load_texts.
    "! Human-readable description of an authorization check, composed as
    "! "object text — activity text" with any further authorization field
    "! ids appended in parentheses. Falls back to the raw object / code
    "! whenever a text does not resolve.
    METHODS describe
      IMPORTING object         TYPE string
                activity       TYPE string
      RETURNING VALUE(text)    TYPE string.
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
    load_texts( ).
    LOOP AT result-checks INTO DATA(check).
      APPEND VALUE #(
        auth_object  = check-object
        description  = describe( object   = check-object
                                 activity = check-details )
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

  METHOD load_texts.
    " Authorization object texts — restricted to the objects actually present.
    DATA objects TYPE SORTED TABLE OF tobjt-object WITH UNIQUE KEY table_line.
    LOOP AT result-checks INTO DATA(check) WHERE object IS NOT INITIAL.
      INSERT CONV tobjt-object( check-object ) INTO TABLE objects.
    ENDLOOP.

    IF objects IS NOT INITIAL.
      SELECT object, langu, ttext FROM tobjt
        FOR ALL ENTRIES IN @objects
        WHERE object = @objects-table_line
          AND ( langu = @sy-langu OR langu = 'E' )
        INTO TABLE @DATA(object_rows).
      " Logon language wins; English fills the gaps.
      LOOP AT object_rows INTO DATA(object_row) WHERE langu = sy-langu.
        INSERT VALUE #( key = object_row-object text = object_row-ttext ) INTO TABLE object_texts.
      ENDLOOP.
      LOOP AT object_rows INTO object_row WHERE langu = 'E'.
        IF NOT line_exists( object_texts[ key = object_row-object ] ).
          INSERT VALUE #( key = object_row-object text = object_row-ttext ) INTO TABLE object_texts.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " Activity texts — the activity master (TACTT) is small; load logon + English.
    SELECT actvt, spras, ltext FROM tactt
      WHERE spras = @sy-langu OR spras = 'E'
      INTO TABLE @DATA(activity_rows).
    LOOP AT activity_rows INTO DATA(activity_row) WHERE spras = sy-langu.
      INSERT VALUE #( key = activity_row-actvt text = activity_row-ltext ) INTO TABLE activity_texts.
    ENDLOOP.
    LOOP AT activity_rows INTO activity_row WHERE spras = 'E'.
      IF NOT line_exists( activity_texts[ key = activity_row-actvt ] ).
        INSERT VALUE #( key = activity_row-actvt text = activity_row-ltext ) INTO TABLE activity_texts.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD describe.
    IF object IS INITIAL.
      RETURN.
    ENDIF.

    DATA(object_text) = VALUE #( object_texts[ key = to_upper( object ) ]-text DEFAULT object ).

    " Parse the "ID=VALUE, ID=VALUE, ..." activity string built by the detector.
    DATA activity_code TYPE string.
    DATA other_ids     TYPE string_table.
    SPLIT activity AT `, ` INTO TABLE DATA(parts).
    LOOP AT parts INTO DATA(part).
      IF NOT part CS `=`.
        CONTINUE.
      ENDIF.
      SPLIT part AT `=` INTO DATA(id) DATA(value).
      IF id = 'ACTVT'.
        activity_code = value.
      ELSE.
        APPEND id TO other_ids.
      ENDIF.
    ENDLOOP.

    text = object_text.
    IF activity_code IS NOT INITIAL.
      DATA(activity_text) = VALUE #( activity_texts[ key = activity_code ]-text DEFAULT activity_code ).
      text = |{ object_text } — { activity_text }|.
    ENDIF.

    IF other_ids IS NOT INITIAL.
      text = |{ text } ({ concat_lines_of( table = other_ids sep = `, ` ) })|.
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
      ( field = 'AUTH_OBJECT'  short = 'Object'   med = 'Auth. object'  long = 'Authorization object' )
      ( field = 'DESCRIPTION'  short = 'Descr.'   med = 'Description'   long = 'Description' )
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
