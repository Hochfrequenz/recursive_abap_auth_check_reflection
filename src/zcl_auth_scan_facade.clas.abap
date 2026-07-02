CLASS zcl_auth_scan_facade DEFINITION
  PUBLIC
  CREATE PRIVATE.

  PUBLIC SECTION.
    "! Build a facade wired with the production collaborators.
    CLASS-METHODS create
      RETURNING VALUE(facade) TYPE REF TO zcl_auth_scan_facade.

    "! Scan a transaction for reachable authorization checks.
    METHODS run
      IMPORTING transaction   TYPE tcode
                max_depth     TYPE i DEFAULT 100
                scope         TYPE zif_auth_scan_types=>scope
                                DEFAULT zif_auth_scan_types=>scopes-into_standard
      RETURNING VALUE(result) TYPE zif_auth_scan_types=>result
      RAISING   zcx_auth_scan.

    "! Render the retained graph of a result as Graphviz DOT.
    METHODS to_dot
      IMPORTING result     TYPE zif_auth_scan_types=>result
      RETURNING VALUE(dot) TYPE string.

  PRIVATE SECTION.
    DATA engine TYPE REF TO zcl_auth_scan_engine.
ENDCLASS.


CLASS zcl_auth_scan_facade IMPLEMENTATION.

  METHOD create.
    DATA entry         TYPE REF TO zif_auth_scan_entry.
    DATA edge_provider TYPE REF TO zif_auth_scan_edge_provider.
    DATA resolver      TYPE REF TO zif_auth_scan_incl_resolver.
    DATA expander      TYPE REF TO zif_auth_scan_expander.
    DATA detector      TYPE REF TO zif_auth_scan_detector.

    entry         = NEW zcl_auth_scan_entry_resolver( ).
    edge_provider = NEW zcl_auth_scan_xref_edges( ).
    resolver      = NEW zcl_auth_scan_incl_resolver( ).
    expander      = NEW zcl_auth_scan_expander( ).
    detector      = NEW zcl_auth_scan_detector( ).

    facade = NEW #( ).
    facade->engine = NEW zcl_auth_scan_engine( entry         = entry
                                               edge_provider = edge_provider
                                               resolver      = resolver
                                               expander      = expander
                                               detector      = detector ).
  ENDMETHOD.

  METHOD run.
    result = engine->run( transaction = transaction
                          max_depth   = max_depth
                          scope       = scope ).
  ENDMETHOD.

  METHOD to_dot.
    " DOT export (Task 10b) — stub until ZCL_AUTH_SCAN_DOT is implemented.
    RETURN.
  ENDMETHOD.

ENDCLASS.
