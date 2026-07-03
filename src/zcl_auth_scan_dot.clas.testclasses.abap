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
    "! Regression for CX_SY_ARITHMETIC_OVERFLOW in adler32( ): the checksum
    "! high word (b) once got multiplied by 65536 as TYPE i, overflowing for
    "! any b >= 32768. This DOT yields adler32 b = 34481, which used to dump.
    METHODS large_checksum_no_overflow FOR TESTING.
ENDCLASS.

CLASS ltc_kroki IMPLEMENTATION.

  METHOD large_checksum_no_overflow.
    DATA(url) = zcl_auth_scan_dot=>kroki_url( `digraph{ a->b; a->b; a->b; }` ).

    cl_abap_unit_assert=>assert_char_cp(
      act = url
      exp = 'https://kroki.io/graphviz/svg/*'
      msg = 'kroki_url must encode a DOT with a high adler32 checksum without overflowing' ).
  ENDMETHOD.

ENDCLASS.
