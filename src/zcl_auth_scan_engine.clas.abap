*----------------------------------------------------------------------*
* recursive_abap_auth_check_reflection
* https://github.com/Hochfrequenz/recursive_abap_auth_check_reflection
* SPDX-License-Identifier: MIT
*----------------------------------------------------------------------*
CLASS zcl_auth_scan_engine DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Reachability engine. Collaborators are injected so the BFS can be
    "! unit-tested with fakes.
    METHODS constructor
      IMPORTING entry         TYPE REF TO zif_auth_scan_entry
                edge_provider TYPE REF TO zif_auth_scan_edge_provider
                resolver      TYPE REF TO zif_auth_scan_incl_resolver
                expander      TYPE REF TO zif_auth_scan_expander
                detector      TYPE REF TO zif_auth_scan_detector.

    "! Walk the call graph reachable from a transaction and collect every
    "! authorization check, the retained graph, and unresolved frontier edges.
    METHODS run
      IMPORTING transaction   TYPE tcode
                max_depth     TYPE i DEFAULT 100
                scope         TYPE zif_auth_scan_types=>scope
                                DEFAULT zif_auth_scan_types=>scopes-into_standard
      RETURNING VALUE(result) TYPE zif_auth_scan_types=>result
      RAISING   zcx_auth_scan.

  PRIVATE SECTION.
    DATA entry         TYPE REF TO zif_auth_scan_entry.
    DATA edge_provider TYPE REF TO zif_auth_scan_edge_provider.
    DATA resolver      TYPE REF TO zif_auth_scan_incl_resolver.
    DATA expander      TYPE REF TO zif_auth_scan_expander.
    DATA detector      TYPE REF TO zif_auth_scan_detector.

    TYPES: BEGIN OF work_item,
             include        TYPE progname,
             label          TYPE string,
             kind           TYPE zif_auth_scan_types=>edge_kind,
             depth          TYPE i,
             is_standard    TYPE abap_bool,
             is_provisional TYPE abap_bool,
             path           TYPE string,
           END OF work_item.

    "! Name-based classification: Z*/Y* or a registered namespace (/.../) is
    "! custom; everything else is SAP standard. (TADIR-based refinement later.)
    METHODS is_standard_include
      IMPORTING include       TYPE progname
      RETURNING VALUE(result) TYPE abap_bool.

    "! Human label for an edge target: object=>method, or object.
    METHODS edge_label
      IMPORTING edge          TYPE zif_auth_scan_types=>edge
      RETURNING VALUE(result) TYPE string.
ENDCLASS.


CLASS zcl_auth_scan_engine IMPLEMENTATION.

  METHOD constructor.
    me->entry         = entry.
    me->edge_provider = edge_provider.
    me->resolver      = resolver.
    me->expander      = expander.
    me->detector      = detector.
  ENDMETHOD.


  METHOD run.
    result-transaction = transaction.

    DATA visited  TYPE SORTED TABLE OF progname WITH UNIQUE KEY table_line.
    DATA worklist TYPE STANDARD TABLE OF work_item WITH EMPTY KEY.

    LOOP AT entry->resolve( transaction ) INTO DATA(seed).
      APPEND VALUE #( include     = seed
                      label       = |{ seed }|
                      depth       = 0
                      is_standard = is_standard_include( seed )
                      path        = |{ transaction }| ) TO worklist.
    ENDLOOP.

    WHILE worklist IS NOT INITIAL.
      DATA(item) = worklist[ 1 ].
      DELETE worklist INDEX 1.

      IF line_exists( visited[ table_line = item-include ] ).
        CONTINUE.
      ENDIF.
      INSERT item-include INTO TABLE visited.

      APPEND VALUE #( include        = item-include
                      label          = item-label
                      kind           = item-kind
                      depth          = item-depth
                      is_standard    = item-is_standard
                      is_provisional = item-is_provisional
                      path           = item-path ) TO result-nodes.

      IF item-depth > max_depth.
        result-max_depth_hit = abap_true.
        APPEND VALUE #( source_include = item-include
                        reason         = |maximum recursion depth { max_depth } reached|
                        path           = item-path ) TO result-frontier.
        CONTINUE.
      ENDIF.

      LOOP AT detector->scan_include( item-include ) INTO DATA(statement_check).
        statement_check-path           = item-path.
        statement_check-is_provisional = item-is_provisional.
        APPEND statement_check TO result-checks.
      ENDLOOP.

      LOOP AT edge_provider->get_edges( item-include ) INTO DATA(edge).
        DATA(classification) = detector->classify_edge( edge ).
        IF classification-is_check = abap_true.
          DATA(api_check) = classification-check.
          api_check-path           = item-path.
          api_check-is_provisional = item-is_provisional.
          APPEND api_check TO result-checks.
        ENDIF.

        DATA targets     TYPE zif_auth_scan_types=>includes.
        DATA provisional TYPE abap_bool.
        CLEAR: targets, provisional.

        IF edge-kind = zif_auth_scan_types=>edge_kinds-dynamic
        OR edge-kind = zif_auth_scan_types=>edge_kinds-badi.
          DATA(expansion) = expander->expand( edge ).
          targets     = expansion-includes.
          provisional = abap_true.
          IF expansion-has_frontier = abap_true.
            DATA(dynamic_frontier) = expansion-frontier.
            dynamic_frontier-path = item-path.
            APPEND dynamic_frontier TO result-frontier.
          ENDIF.
        ELSE.
          DATA(resolution) = resolver->resolve( edge ).
          IF resolution-is_unresolved = abap_true.
            APPEND VALUE #( source_include = item-include
                            kind           = edge-kind
                            reason         = |unresolved target { edge_label( edge ) }|
                            raw            = edge-target-raw
                            path           = item-path ) TO result-frontier.
          ELSE.
            targets = resolution-includes.
          ENDIF.
        ENDIF.

        DATA(child_provisional) = COND abap_bool(
          WHEN item-is_provisional = abap_true OR provisional = abap_true
          THEN abap_true
          ELSE abap_false ).

        LOOP AT targets INTO DATA(target).
          DATA(target_is_standard) = is_standard_include( target ).

          APPEND VALUE #( from_include   = item-include
                          to_include     = target
                          kind           = edge-kind
                          label          = edge_label( edge )
                          is_provisional = child_provisional ) TO result-graph_edges.

          IF scope = zif_auth_scan_types=>scopes-custom_only
          AND target_is_standard = abap_true.
            APPEND VALUE #( source_include = item-include
                            kind           = edge-kind
                            reason         = |custom/standard boundary: { edge_label( edge ) }|
                            path           = item-path ) TO result-frontier.
            CONTINUE.
          ENDIF.

          APPEND VALUE #( include        = target
                          label          = edge_label( edge )
                          kind           = edge-kind
                          depth          = item-depth + 1
                          is_standard    = target_is_standard
                          is_provisional = child_provisional
                          path           = |{ item-path } -> { edge_label( edge ) }| ) TO worklist.
        ENDLOOP.
      ENDLOOP.
    ENDWHILE.

    result-nodes_seen = lines( visited ).
  ENDMETHOD.


  METHOD is_standard_include.
    DATA(name) = to_upper( include ).
    result = COND abap_bool(
      WHEN name CP 'Z*' OR name CP 'Y*' OR name CP '/*'
      THEN abap_false
      ELSE abap_true ).
  ENDMETHOD.


  METHOD edge_label.
    result = COND string(
      WHEN edge-target-sub_name IS NOT INITIAL
      THEN |{ edge-target-object }=>{ edge-target-sub_name }|
      ELSE edge-target-object ).
  ENDMETHOD.

ENDCLASS.