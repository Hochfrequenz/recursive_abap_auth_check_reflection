*----------------------------------------------------------------------*
* recursive_abap_auth_check_reflection
* https://github.com/Hochfrequenz/recursive_abap_auth_check_reflection
* SPDX-License-Identifier: MIT
*----------------------------------------------------------------------*
*"* ABAP Unit — end-to-end acceptance tests (live fixtures).
*"* NOTE: abapGit does not re-import this test include on pull; after a pull it
*"* must be re-applied to SAP via ADT (create_test_include + set_include_source).

CLASS ltc_acceptance DEFINITION FINAL FOR TESTING
  DURATION LONG
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS ucom_customer_finds_e_instln FOR TESTING RAISING zcx_auth_scan.
    METHODS emmacl_finds_b_emma_cas      FOR TESTING RAISING zcx_auth_scan.
ENDCLASS.

CLASS ltc_acceptance IMPLEMENTATION.

  METHOD ucom_customer_finds_e_instln.
    DATA(result) = zcl_auth_scan_facade=>create( )->run(
      transaction = '/UCOM/CUSTOMER'
      max_depth   = 15
      scope       = zif_auth_scan_types=>scopes-custom_only ).

    cl_abap_unit_assert=>assert_true(
      act = xsdbool( line_exists( result-checks[ type   = zif_auth_scan_types=>check_types-function_module
                                                 object = 'E_INSTLN' ] ) )
      msg = 'ISU_AUTHORITY_CHECK on E_INSTLN was not recovered from /UCOM/CUSTOMER' ).
  ENDMETHOD.

  METHOD emmacl_finds_b_emma_cas.
    DATA(result) = zcl_auth_scan_facade=>create( )->run(
      transaction = 'EMMACL'
      max_depth   = 15
      scope       = zif_auth_scan_types=>scopes-custom_only ).

    cl_abap_unit_assert=>assert_true(
      act = xsdbool( line_exists( result-checks[ type   = zif_auth_scan_types=>check_types-statement
                                                 object = 'B_EMMA_CAS' ] ) )
      msg = 'AUTHORITY-CHECK on B_EMMA_CAS was not recovered from EMMACL' ).
  ENDMETHOD.

ENDCLASS.