CLASS zcx_auth_scan DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_t100_message.
    INTERFACES if_t100_dyn_msg.

    METHODS constructor
      IMPORTING textid   LIKE if_t100_message=>t100key OPTIONAL
                previous LIKE previous               OPTIONAL.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS zcx_auth_scan IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( previous = previous ).
    if_t100_message~t100key = COND #( WHEN textid IS INITIAL
                                      THEN if_t100_message=>default_textid
                                      ELSE textid ).
  ENDMETHOD.

ENDCLASS.

