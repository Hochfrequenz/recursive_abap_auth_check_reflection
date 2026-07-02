*----------------------------------------------------------------------*
* recursive_abap_auth_check_reflection
* https://github.com/Hochfrequenz/recursive_abap_auth_check_reflection
* SPDX-License-Identifier: MIT
*----------------------------------------------------------------------*
CLASS zcl_auth_scan_detector DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_auth_scan_detector.

  PRIVATE SECTION.
    TYPES: BEGIN OF const_entry,
             name  TYPE string,
             value TYPE string,
           END OF const_entry,
           const_map TYPE HASHED TABLE OF const_entry WITH UNIQUE KEY name.
    TYPES: BEGIN OF auth_fm,
             name         TYPE string,
             object_arg   TYPE string,
             fixed_object TYPE string,
           END OF auth_fm,
           auth_fms TYPE STANDARD TABLE OF auth_fm WITH EMPTY KEY.
    TYPES: BEGIN OF resolved,
             value TYPE string,
             known TYPE abap_bool,
           END OF resolved.

    "! Build a name->value map of literal-valued local CONSTANTS from source.
    METHODS local_constants
      IMPORTING source        TYPE string_table
      RETURNING VALUE(result) TYPE const_map.
    "! Registered authorization function modules and their object argument.
    METHODS registered_function_modules
      RETURNING VALUE(result) TYPE auth_fms.
    "! Resolve a token to a literal value (string literal, local constant, or
    "! a global constant/attribute via dynamic ASSIGN).
    METHODS resolve_token
      IMPORTING token         TYPE stokes
                constants     TYPE const_map
      RETURNING VALUE(result) TYPE resolved.
    METHODS strip_quotes
      IMPORTING value         TYPE string
      RETURNING VALUE(result) TYPE string.
ENDCLASS.


CLASS zcl_auth_scan_detector IMPLEMENTATION.

  METHOD zif_auth_scan_detector~classify_edge.
    " Detection is source-based (see scan_include); edges are not classified here.
    RETURN.
  ENDMETHOD.

  METHOD zif_auth_scan_detector~scan_include.
    DATA source TYPE string_table.
    READ REPORT include INTO source.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA(constants) = local_constants( source ).
    DATA(function_modules) = registered_function_modules( ).

    DATA tokens     TYPE STANDARD TABLE OF stokes.
    DATA statements TYPE STANDARD TABLE OF sstmnt.
    SCAN ABAP-SOURCE source TOKENS INTO tokens STATEMENTS INTO statements.

    LOOP AT statements INTO DATA(statement).
      IF statement-from IS INITIAL OR statement-from > statement-to.
        CONTINUE.
      ENDIF.
      DATA(keyword) = to_upper( tokens[ statement-from ]-str ).

      IF keyword = 'AUTHORITY-CHECK'.
        DATA(index) = statement-from.
        WHILE index < statement-to.
          IF to_upper( tokens[ index ]-str ) = 'OBJECT'.
            DATA(object) = resolve_token( token = tokens[ index + 1 ] constants = constants ).
            APPEND VALUE #( type         = zif_auth_scan_types=>check_types-statement
                            object       = object-value
                            object_known = object-known
                            details      = 'AUTHORITY-CHECK'
                            include      = include
                            line         = tokens[ statement-from ]-row ) TO checks.
            EXIT.
          ENDIF.
          index = index + 1.
        ENDWHILE.

      ELSEIF keyword = 'CALL'
         AND statement-from + 2 <= statement-to
         AND to_upper( tokens[ statement-from + 1 ]-str ) = 'FUNCTION'.
        DATA(fm_name) = to_upper( strip_quotes( tokens[ statement-from + 2 ]-str ) ).
        READ TABLE function_modules WITH KEY name = fm_name INTO DATA(fm).
        IF sy-subrc = 0.
          DATA(check) = VALUE zif_auth_scan_types=>auth_check(
            type    = zif_auth_scan_types=>check_types-function_module
            details = fm_name
            include = include
            line    = tokens[ statement-from ]-row ).
          IF fm-fixed_object IS NOT INITIAL.
            check-object       = fm-fixed_object.
            check-object_known = abap_true.
          ELSEIF fm-object_arg IS NOT INITIAL.
            DATA(pos) = statement-from.
            WHILE pos < statement-to.
              IF to_upper( tokens[ pos ]-str ) = fm-object_arg.
                DATA(value_index) = pos + 1.
                IF value_index <= statement-to AND tokens[ value_index ]-str = '='.
                  value_index = value_index + 1.
                ENDIF.
                IF value_index <= statement-to.
                  DATA(value) = resolve_token( token = tokens[ value_index ] constants = constants ).
                  check-object       = value-value.
                  check-object_known = value-known.
                ENDIF.
                EXIT.
              ENDIF.
              pos = pos + 1.
            ENDWHILE.
          ENDIF.
          APPEND check TO checks.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD local_constants.
    LOOP AT source INTO DATA(line).
      FIND FIRST OCCURRENCE OF PCRE '([\w/]+)\s+TYPE\s+[\w/]+\s+VALUE\s+''([^'']*)'''
        IN line IGNORING CASE SUBMATCHES DATA(name) DATA(value).
      IF sy-subrc = 0.
        INSERT VALUE #( name = to_upper( name ) value = value ) INTO TABLE result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD registered_function_modules.
    result = VALUE #(
      ( name = 'AUTHORITY_CHECK'       object_arg   = 'OBJECT' )
      ( name = 'ISU_AUTHORITY_CHECK'   object_arg   = 'X_OBJECT' )
      ( name = 'AUTHORITY_CHECK_TCODE' fixed_object = 'S_TCODE' )
      ( name = 'VIEW_AUTHORITY_CHECK'  object_arg   = 'VIEW' ) ).
  ENDMETHOD.

  METHOD resolve_token.
    DATA(raw) = condense( token-str ).
    IF strlen( raw ) >= 1 AND ( raw(1) = '''' OR raw(1) = '`' ).
      result = VALUE #( value = strip_quotes( raw ) known = abap_true ).
      RETURN.
    ENDIF.
    IF token-type = 'S'.
      result = VALUE #( value = raw known = abap_true ).
      RETURN.
    ENDIF.
    DATA(name) = to_upper( raw ).
    READ TABLE constants WITH KEY name = name INTO DATA(entry).
    IF sy-subrc = 0.
      result = VALUE #( value = entry-value known = abap_true ).
      RETURN.
    ENDIF.
    ASSIGN (raw) TO FIELD-SYMBOL(<value>).
    IF sy-subrc = 0.
      result = VALUE #( value = condense( |{ <value> }| ) known = abap_true ).
      RETURN.
    ENDIF.
    result-known = abap_false.
  ENDMETHOD.

  METHOD strip_quotes.
    result = value.
    IF strlen( result ) >= 2 AND ( result(1) = '''' OR result(1) = '`' ).
      result = substring( val = result off = 1 len = strlen( result ) - 2 ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.