CLASS zcl_auth_scan_entry_resolver DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_auth_scan_entry.
ENDCLASS.


CLASS zcl_auth_scan_entry_resolver IMPLEMENTATION.

  METHOD zif_auth_scan_entry~resolve.
    SELECT SINGLE pgmna FROM tstc WHERE tcode = @transaction INTO @DATA(program).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_auth_scan MESSAGE e001(zauth_scan) WITH transaction.
    ENDIF.
    IF program IS INITIAL.
      RAISE EXCEPTION TYPE zcx_auth_scan MESSAGE e002(zauth_scan) WITH transaction.
    ENDIF.

    includes = VALUE #( ( CONV progname( program ) ) ).

    " the program's own authored includes (report INCLUDEs), not pulled-in pools
    SELECT include FROM d010inc
      WHERE master  = @program
        AND include LIKE @( |{ program }%| )
      INTO TABLE @DATA(sub_includes).
    LOOP AT sub_includes INTO DATA(sub).
      IF NOT line_exists( includes[ table_line = sub-include ] ).
        APPEND sub-include TO includes.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
