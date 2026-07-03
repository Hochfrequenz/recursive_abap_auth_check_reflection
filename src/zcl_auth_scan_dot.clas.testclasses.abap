*----------------------------------------------------------------------*
* recursive_abap_auth_check_reflection
* https://github.com/Hochfrequenz/recursive_abap_auth_check_reflection
* SPDX-License-Identifier: MIT
*----------------------------------------------------------------------*
*"* ABAP Unit — kroki URL encoding.
*"* NOTE: abapGit does not re-import this test include on pull; after a pull it
*"* must be re-applied to SAP via ADT (create_test_include + set_include_source).

CLASS ltc_kroki DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    "! compress_binary must return a BARE DEFLATE stream (RFC 1951): no zlib
    "! (0x78..) header and no gzip (0x1F8B) framing. kroki_url relies on this to
    "! wrap it as zlib. If a kernel ever changes this, the guard fails loudly.
    METHODS compress_binary_bare_deflate FOR TESTING.
    "! The wrapped body must inflate back to the source — proving it is the
    "! valid DEFLATE payload kroki's zlib inflater expects.
    METHODS deflate_body_round_trips FOR TESTING.
    "! Regression for CX_SY_ARITHMETIC_OVERFLOW in adler32( ) (b * 65536 as
    "! TYPE i overflowed for b >= 32768). This DOT yields adler32 b = 34481.
    METHODS large_checksum_no_overflow FOR TESTING.

    METHODS deflate_of
      IMPORTING source         TYPE string
      RETURNING VALUE(deflate) TYPE xstring.
ENDCLASS.

CLASS ltc_kroki IMPLEMENTATION.

  METHOD deflate_of.
    cl_abap_gzip=>compress_binary(
      EXPORTING raw_in   = cl_abap_codepage=>convert_to( source )
      IMPORTING gzip_out = deflate ).
  ENDMETHOD.

  METHOD compress_binary_bare_deflate.
    DATA(head) = |{ deflate_of( `digraph{ a->b }` ) }|.
    cl_abap_unit_assert=>assert_char_np(
      act = head exp = '78*'
      msg = 'compress_binary returned a zlib-framed stream, not bare DEFLATE' ).
    cl_abap_unit_assert=>assert_char_np(
      act = head exp = '1F8B*'
      msg = 'compress_binary returned a gzip-framed stream, not bare DEFLATE' ).
  ENDMETHOD.

  METHOD deflate_body_round_trips.
    DATA(source)  = `digraph{ a->b; b->c; c->a }`.
    DATA(deflate) = deflate_of( source ).
    cl_abap_gzip=>decompress_binary( EXPORTING gzip_in  = deflate
                                     IMPORTING raw_out  = DATA(back) ).
    cl_abap_unit_assert=>assert_equals(
      act = cl_abap_codepage=>convert_from( back )
      exp = source
      msg = 'DEFLATE body must inflate back to the source' ).
  ENDMETHOD.

  METHOD large_checksum_no_overflow.
    DATA(url) = zcl_auth_scan_dot=>kroki_url( `digraph{ a->b; a->b; a->b; }` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = url
      exp = 'https://kroki.io/graphviz/svg/*'
      msg = 'kroki_url must encode a DOT with a high adler32 checksum without overflowing' ).
  ENDMETHOD.

ENDCLASS.
