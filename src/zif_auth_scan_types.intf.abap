*----------------------------------------------------------------------*
* recursive_abap_auth_check_reflection
* https://github.com/Hochfrequenz/recursive_abap_auth_check_reflection
* SPDX-License-Identifier: MIT
*----------------------------------------------------------------------*
INTERFACE zif_auth_scan_types
  PUBLIC.

  "! Kind of a call-graph edge.
  TYPES edge_kind TYPE c LENGTH 1.

  CONSTANTS:
    "! Edge kinds: method / function-module / perform / interface / dynamic / BAdI.
    BEGIN OF edge_kinds,
      method    TYPE edge_kind VALUE 'M',
      function  TYPE edge_kind VALUE 'C',
      perform   TYPE edge_kind VALUE 'P',
      interface TYPE edge_kind VALUE 'I',
      dynamic   TYPE edge_kind VALUE 'D',
      badi      TYPE edge_kind VALUE 'B',
    END OF edge_kinds.

  "! Kind of an authorization check.
  TYPES check_type TYPE c LENGTH 1.

  CONSTANTS:
    "! Check types: classic statement / class-based / function-module.
    BEGIN OF check_types,
      statement       TYPE check_type VALUE 'S',
      class_based     TYPE check_type VALUE 'K',
      function_module TYPE check_type VALUE 'F',
    END OF check_types.

  "! Reachability scope.
  TYPES scope TYPE c LENGTH 1.

  CONSTANTS:
    "! Scope: stop at the custom/standard boundary, or descend into standard (default).
    BEGIN OF scopes,
      custom_only   TYPE scope VALUE 'C',
      into_standard TYPE scope VALUE 'S',
    END OF scopes.

  TYPES:
    "! List of program includes.
    includes TYPE STANDARD TABLE OF progname WITH EMPTY KEY,

    "! A referenced object, parsed from the cross-reference index.
    BEGIN OF object_ref,
      otype    TYPE string,
      object   TYPE string,
      sub_name TYPE string,
      raw      TYPE string,
    END OF object_ref,

    "! An outgoing call edge from one include.
    BEGIN OF edge,
      source_include TYPE progname,
      kind           TYPE edge_kind,
      target         TYPE object_ref,
    END OF edge,
    edges TYPE STANDARD TABLE OF edge WITH EMPTY KEY,

    "! A visited code-unit node in the reachability graph.
    "! label is the human-readable unit (REPORT x / class=>method / FUNCTION x
    "! / FORM x); kind is how it is reached (initial/blank for the entry unit).
    BEGIN OF node,
      include        TYPE progname,
      label          TYPE string,
      kind           TYPE edge_kind,
      depth          TYPE i,
      is_standard    TYPE abap_bool,
      is_provisional TYPE abap_bool,
      path           TYPE string,
    END OF node,
    nodes TYPE STANDARD TABLE OF node WITH EMPTY KEY,

    "! One detected authorization check. The detector fills type / object /
    "! object_known / details / include / unit / line; the engine augments
    "! path and is_provisional from the reaching node.
    BEGIN OF auth_check,
      type           TYPE check_type,
      object         TYPE string,
      object_known   TYPE abap_bool,
      details        TYPE string,
      include        TYPE progname,
      unit           TYPE string,
      line           TYPE i,
      path           TYPE string,
      is_provisional TYPE abap_bool,
    END OF auth_check,
    auth_checks TYPE STANDARD TABLE OF auth_check WITH EMPTY KEY,

    "! An unresolved dynamic/BAdI edge - a documented blind spot.
    BEGIN OF frontier,
      source_include TYPE progname,
      kind           TYPE edge_kind,
      reason         TYPE string,
      raw            TYPE string,
      path           TYPE string,
    END OF frontier,
    frontiers TYPE STANDARD TABLE OF frontier WITH EMPTY KEY,

    "! A resolved graph edge, retained for DOT export.
    BEGIN OF graph_edge,
      from_include   TYPE progname,
      to_include     TYPE progname,
      kind           TYPE edge_kind,
      label          TYPE string,
      is_provisional TYPE abap_bool,
    END OF graph_edge,
    graph_edges TYPE STANDARD TABLE OF graph_edge WITH EMPTY KEY,

    "! Outcome of resolving an edge target to implementing include(s).
    BEGIN OF resolution,
      includes      TYPE includes,
      is_unresolved TYPE abap_bool,
    END OF resolution,

    "! Outcome of expanding a dynamic/BAdI edge.
    BEGIN OF expansion,
      includes     TYPE includes,
      frontier     TYPE frontier,
      has_frontier TYPE abap_bool,
    END OF expansion,

    "! Outcome of classifying an edge as an authorization-API call.
    BEGIN OF classification,
      is_check TYPE abap_bool,
      check    TYPE auth_check,
    END OF classification,

    "! Full scan result: inventory, frontier, retained graph and stats.
    BEGIN OF result,
      transaction   TYPE tcode,
      checks        TYPE auth_checks,
      frontier      TYPE frontiers,
      nodes         TYPE nodes,
      graph_edges   TYPE graph_edges,
      nodes_seen    TYPE i,
      max_depth_hit TYPE abap_bool,
    END OF result.

ENDINTERFACE.