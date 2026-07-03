*----------------------------------------------------------------------*
* recursive_abap_auth_check_reflection
* https://github.com/Hochfrequenz/recursive_abap_auth_check_reflection
* SPDX-License-Identifier: MIT
*----------------------------------------------------------------------*
CLASS zcl_auth_scan_dot DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Render the retained graph of a scan result as Graphviz DOT.
    "! Output is deterministic: nodes/edges/checks are emitted in a stable
    "! sorted order so the same graph always yields byte-identical DOT.
    METHODS to_dot
      IMPORTING result     TYPE zif_auth_scan_types=>result
      RETURNING VALUE(dot) TYPE string.

    "! Build a kroki.io render URL for a DOT string (zlib-deflate + base64url).
    "! The link renders in a browser even if SAP itself cannot reach kroki.io.
    CLASS-METHODS kroki_url
      IMPORTING dot        TYPE string
                format     TYPE string DEFAULT 'svg'
      RETURNING VALUE(url) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS adler32
      IMPORTING data          TYPE xstring
      RETURNING VALUE(result) TYPE xstring.
    METHODS node_id
      IMPORTING include    TYPE progname
      RETURNING VALUE(id)  TYPE string.
    METHODS escape
      IMPORTING text       TYPE string
      RETURNING VALUE(out) TYPE string.
ENDCLASS.


CLASS zcl_auth_scan_dot IMPLEMENTATION.

  METHOD to_dot.
    DATA lines TYPE string_table.
    APPEND `digraph auth_scan {` TO lines.
    APPEND `  rankdir=LR;` TO lines.
    APPEND `  node [fontname="Courier"];` TO lines.

    " code-unit nodes (deterministic order, de-duplicated by include)
    DATA(nodes) = result-nodes.
    SORT nodes BY include.
    DELETE ADJACENT DUPLICATES FROM nodes COMPARING include.
    LOOP AT nodes INTO DATA(node).
      DATA(label) = escape( COND #( WHEN node-label IS NOT INITIAL
                                    THEN node-label
                                    ELSE CONV string( node-include ) ) ).
      DATA(style) = COND string(
        WHEN node-is_provisional = abap_true THEN ` style=dashed color="#888888"`
        WHEN node-is_standard    = abap_true THEN ` color="#4477aa"`
        ELSE                                      ` color="#222222"` ).
      APPEND |  "n_{ node_id( node-include ) }" [label="{ label }"{ style }];| TO lines.
    ENDLOOP.

    " authorization-check nodes, each linked from its containing code node
    DATA(checks) = result-checks.
    SORT checks BY include type object line.
    DATA index TYPE i.
    LOOP AT checks INTO DATA(check).
      index = index + 1.
      DATA(kind_text) = COND string(
        WHEN check-type = zif_auth_scan_types=>check_types-statement       THEN `AUTHORITY-CHECK`
        WHEN check-type = zif_auth_scan_types=>check_types-function_module THEN `AUTH FM`
        WHEN check-type = zif_auth_scan_types=>check_types-class_based      THEN `AUTH CLASS`
        ELSE                                                                    `AUTH` ).
      DATA(object_text) = COND string( WHEN check-object_known = abap_true THEN check-object ELSE `?` ).
      APPEND |  "chk_{ index }" [label="{ escape( kind_text ) }\\n{ escape( object_text ) }" shape=box style=filled fillcolor="#ffdddd"];| TO lines.
      APPEND |  "n_{ node_id( check-include ) }" -> "chk_{ index }" [color="#cc0000" style=bold];| TO lines.
    ENDLOOP.

    " code -> code call edges (deterministic order, de-duplicated)
    DATA(graph_edges) = result-graph_edges.
    SORT graph_edges BY from_include to_include label.
    DELETE ADJACENT DUPLICATES FROM graph_edges COMPARING from_include to_include label.
    LOOP AT graph_edges INTO DATA(edge).
      DATA(edge_style) = COND string( WHEN edge-is_provisional = abap_true THEN ` style=dashed` ELSE `` ).
      APPEND |  "n_{ node_id( edge-from_include ) }" -> "n_{ node_id( edge-to_include ) }" [label="{ escape( edge-label ) }"{ edge_style }];| TO lines.
    ENDLOOP.

    APPEND `}` TO lines.
    dot = concat_lines_of( table = lines sep = |{ cl_abap_char_utilities=>newline }| ).
  ENDMETHOD.

  METHOD node_id.
    id = to_lower( include ).
    REPLACE ALL OCCURRENCES OF PCRE '[^a-z0-9]' IN id WITH `_`.
  ENDMETHOD.

  METHOD escape.
    out = text.
    REPLACE ALL OCCURRENCES OF `\` IN out WITH `\\`.
    REPLACE ALL OCCURRENCES OF `"` IN out WITH `\"`.
  ENDMETHOD.

  METHOD kroki_url.
    " kroki expects: base64url( zlib-stream( source ) ), i.e. RFC 1950.
    DATA(raw) = cl_abap_codepage=>convert_to( dot ).

    " cl_abap_gzip=>compress_binary yields a bare DEFLATE stream (RFC 1951) —
    " no header, no checksum. kroki needs a zlib stream (RFC 1950), so wrap the
    " DEFLATE body as: 0x789C + DEFLATE + adler32(source).
    DATA deflate TYPE xstring.
    cl_abap_gzip=>compress_binary( EXPORTING raw_in   = raw
                                   IMPORTING gzip_out = deflate ).

    DATA zlib_header TYPE x LENGTH 2 VALUE '789C'.
    DATA(header)   = CONV xstring( zlib_header ).
    DATA(checksum) = adler32( raw ).
    DATA zlib TYPE xstring.
    CONCATENATE header deflate checksum INTO zlib IN BYTE MODE.

    DATA(encoded) = cl_http_utility=>encode_x_base64( zlib ).
    REPLACE ALL OCCURRENCES OF `+` IN encoded WITH `-`.
    REPLACE ALL OCCURRENCES OF `/` IN encoded WITH `_`.
    REPLACE ALL OCCURRENCES OF `=` IN encoded WITH ``.

    url = |https://kroki.io/graphviz/{ format }/{ encoded }|.
  ENDMETHOD.

  METHOD adler32.
    CONSTANTS modulo TYPE i VALUE 65521.
    DATA a TYPE i VALUE 1.
    DATA b TYPE i VALUE 0.
    DATA offset TYPE i.
    DATA(length) = xstrlen( data ).
    WHILE offset < length.
      a = ( a + data+offset(1) ) MOD modulo.
      b = ( b + a ) MOD modulo.
      offset = offset + 1.
    ENDWHILE.

    " adler32 = (b << 16) | a, stored big-endian. a and b are each < 65521, so
    " pack their two bytes directly. (Computing b * 65536 first would overflow
    " TYPE i whenever b >= 32768 — CX_SY_ARITHMETIC_OVERFLOW.)
    DATA bytes TYPE x LENGTH 4.
    bytes+0(1) = b DIV 256.
    bytes+1(1) = b MOD 256.
    bytes+2(1) = a DIV 256.
    bytes+3(1) = a MOD 256.
    result = bytes.
  ENDMETHOD.

ENDCLASS.