*&---------------------------------------------------------------------*
*& Report z_auth_scan
*&---------------------------------------------------------------------*
*& Recursive authorization-check scanner: given a transaction, walk the
*& reachable call graph and list every authorization check found in it.
*&---------------------------------------------------------------------*
REPORT z_auth_scan.

PARAMETERS p_tcode TYPE tcode OBLIGATORY.
PARAMETERS p_depth TYPE i DEFAULT 100.
PARAMETERS p_std   RADIOBUTTON GROUP scp DEFAULT 'X'.  " descend into SAP standard
PARAMETERS p_cust  RADIOBUTTON GROUP scp.              " stop at the custom boundary
PARAMETERS p_dot   AS CHECKBOX.                        " render the graph as Graphviz DOT

START-OF-SELECTION.

  DATA(scope) = COND zif_auth_scan_types=>scope(
    WHEN p_cust = abap_true THEN zif_auth_scan_types=>scopes-custom_only
    ELSE                         zif_auth_scan_types=>scopes-into_standard ).

  DATA(facade) = zcl_auth_scan_facade=>create( ).

  TRY.
      DATA(result) = facade->run( transaction = p_tcode
                                  max_depth   = p_depth
                                  scope       = scope ).
    CATCH zcx_auth_scan INTO DATA(error).
      MESSAGE error->get_text( ) TYPE 'E'.
      RETURN.
  ENDTRY.

  IF p_dot = abap_true.
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
    RETURN.
  ENDIF.

  IF result-checks IS INITIAL.
    MESSAGE |No authorization checks found reachable from { p_tcode } | &&
            |({ result-nodes_seen } units scanned).| TYPE 'I'.
  ENDIF.

  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = DATA(alv)
                              CHANGING  t_table      = result-checks ).
      alv->get_functions( )->set_all( ).
      alv->get_columns( )->set_optimize( ).
      alv->display( ).
    CATCH cx_salv_msg INTO DATA(salv_error).
      MESSAGE salv_error->get_text( ) TYPE 'E'.
  ENDTRY.
