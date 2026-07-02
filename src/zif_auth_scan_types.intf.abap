INTERFACE zif_auth_scan_types
  PUBLIC.

  "! Kind of a call-graph edge.
  TYPES ty_edge_kind TYPE c LENGTH 1.

  CONSTANTS:
    "! Edge kinds: method / func-module / perform / interface / dynamic / BAdI.
    BEGIN OF gc_edge_kind,
      method  TYPE ty_edge_kind VALUE 'M',
      func    TYPE ty_edge_kind VALUE 'C',
      perform TYPE ty_edge_kind VALUE 'P',
      intf    TYPE ty_edge_kind VALUE 'I',
      dynamic TYPE ty_edge_kind VALUE 'D',
      badi    TYPE ty_edge_kind VALUE 'B',
    END OF gc_edge_kind.

  "! Kind of an authorization check.
  TYPES ty_check_type TYPE c LENGTH 1.

  CONSTANTS:
    "! Check types: classic statement / class-based / function-module.
    BEGIN OF gc_check_type,
      statement TYPE ty_check_type VALUE 'S',
      class     TYPE ty_check_type VALUE 'K',
      func      TYPE ty_check_type VALUE 'F',
    END OF gc_check_type.

  "! Reachability scope.
  TYPES ty_scope TYPE c LENGTH 1.

  CONSTANTS:
    "! Scope: stop at the custom/standard boundary, or descend into standard (default).
    BEGIN OF gc_scope,
      custom_only   TYPE ty_scope VALUE 'C',
      into_standard TYPE ty_scope VALUE 'S',
    END OF gc_scope.

  TYPES:
    "! List of program includes.
    ty_includes TYPE STANDARD TABLE OF progname WITH EMPTY KEY,

    "! A referenced object (parsed from the cross-reference index).
    BEGIN OF ty_object_ref,
      otype    TYPE string,
      object   TYPE string,
      sub_name TYPE string,
      raw      TYPE string,
    END OF ty_object_ref,

    "! An outgoing call edge from one include.
    BEGIN OF ty_edge,
      source_include TYPE progname,
      kind           TYPE ty_edge_kind,
      target         TYPE ty_object_ref,
    END OF ty_edge,
    ty_edges TYPE STANDARD TABLE OF ty_edge WITH EMPTY KEY,

    "! A visited node in the reachability graph.
    BEGIN OF ty_node,
      include        TYPE progname,
      depth          TYPE i,
      is_standard    TYPE abap_bool,
      is_provisional TYPE abap_bool,
      path           TYPE string,
    END OF ty_node,
    ty_nodes TYPE STANDARD TABLE OF ty_node WITH EMPTY KEY,

    "! One detected authorization check.
    BEGIN OF ty_check,
      check_type     TYPE ty_check_type,
      auth_object    TYPE string,
      object_known   TYPE abap_bool,
      details        TYPE string,
      include        TYPE progname,
      unit_name      TYPE string,
      line           TYPE i,
      path           TYPE string,
      is_provisional TYPE abap_bool,
    END OF ty_check,
    ty_checks TYPE STANDARD TABLE OF ty_check WITH EMPTY KEY,

    "! An unresolved (dynamic/BAdI) edge - a documented blind spot.
    BEGIN OF ty_frontier,
      source_include TYPE progname,
      kind           TYPE ty_edge_kind,
      reason         TYPE string,
      raw            TYPE string,
      path           TYPE string,
    END OF ty_frontier,
    ty_frontiers TYPE STANDARD TABLE OF ty_frontier WITH EMPTY KEY,

    "! A resolved graph edge, retained for DOT export.
    BEGIN OF ty_graph_edge,
      from_include   TYPE progname,
      to_include     TYPE progname,
      kind           TYPE ty_edge_kind,
      label          TYPE string,
      is_provisional TYPE abap_bool,
    END OF ty_graph_edge,
    ty_graph_edges TYPE STANDARD TABLE OF ty_graph_edge WITH EMPTY KEY,

    "! Full scan result: inventory, frontier, retained graph and stats.
    BEGIN OF ty_result,
      tcode         TYPE tcode,
      checks        TYPE ty_checks,
      frontier      TYPE ty_frontiers,
      nodes         TYPE ty_nodes,
      graph_edges   TYPE ty_graph_edges,
      nodes_seen    TYPE i,
      max_depth_hit TYPE abap_bool,
    END OF ty_result.

ENDINTERFACE.
