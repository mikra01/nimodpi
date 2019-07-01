import ../nimodpi
import os
import strutils

# testsetup: win10,instantclient_19_3_x64
# target: 12.2.0.1 PDB and 12.1.0.2(exadata,1n)
# compiler: gcc version 5.1.0 (tdm64-1) 
# TODO: tests against timesten

#[
 this demo contains three examples (no ddl executed)
   - setting clients encoding 
   - simple fetch
   - fetch with fetchRows (additional types double,raw,timestamp)
   - ref_cursor example 
]#

const
  nlsLang: cstring = "WE8ISO8859P15"

include democredentials
include demosql

proc `$`* (p: var dpiTimestamp): string =
  ## string representation of a timestamp column
  "dpiTimestamp: year:" & $p.year & " month:" & $p.month & " day:" & $p.day &
    " minute:" & $p.minute & " second:" & $p.second & " fsecond:" &
        $p.fsecond &
    " tzHOffset:" & $p.tzHourOffset & " tzMinOffset:" & $p.tzMinuteOffset

template `[]`(data: ptr dpiData, idx: int): ptr dpiData =
  ## accesses the row-column by index
  cast[ptr dpiData]((cast[int](data)) + (sizeof(dpiData)*idx))

template toNimString (data: ptr dpiData): untyped =
  var result: string = newString(data.value.asBytes.length)
  copyMem(addr(result[0]), data.value.asBytes.ptr, result.len)
  result

template onSuccessExecute(context: ptr dpiContext, toprobe: untyped,
    body: untyped) =
  ## template to wrap the boilerplate errorinfo code
  var err: dpiErrorInfo
  if toprobe < DpiResult.SUCCESS.ord:
    dpiContext_getError(context, err.addr)
    echo $err
  else:
    body

type
  Column = object
    colVar: ptr dpiVar
    buffer: ptr dpiData
    dpiresult: DpiResult


template newVar(conn: ptr dpiConn, otype: DpiOracleTypes,
    ntype: DpiNativeCTypes, arrSize: int, colLength: int,
                column: ptr Column) =
  ## initialises a new dpiVar and populates the Column-type
  column.dpiresult = DpiResult(dpiConn_newVar(conn, otype.ord, # db coltype
    ntype.ord, # client coltype
  arrSize.uint32, # max array size
    colLength, # size of buffer
    0, # sizeIsBytes
    0, # isArray
    nil, # objType
    column.colVar.addr, # ptr to the variable
    column.buffer.addr        # ptr to buffer array
  ))

template isNull(dat: ptr dpiData): bool =
  if dat.isNull == 1.cint:
    true
  else:
    false

template hasError(colvar: var Column): bool =
  if colvar.dpiresult == DpiResult.SUCCESS:
    false
  else:
    true

template hasError(context: ptr dpiContext, toprobe: untyped): bool =
  if toprobe < DpiResult.SUCCESS.ord:
    true
  else:
    false

var context: ptr dpiContext
var errorinfo: dpiErrorInfo
var versionInfo: dpiVersionInfo
var commonParams: dpiCommonCreateParams
# globals

let errno = dpiContext_create(DPI_MAJOR_VERSION, DPI_MINOR_VERSION, addr(
    context), addr(errorinfo))
if errno == DpiResult.SUCCESS.ord:
  echo "context_created"
  discard dpiContext_initCommonCreateParams(context, commonParams.addr)
  commonParams.encoding = nlsLang
else:
  echo "unable to create context: " & $errorinfo

discard dpiContext_getClientVersion(context, addr(versionInfo))
echo "client_version: " & $versionInfo.versionNum

var conn: ptr dpiConn

# connectionstrings could be from tns definitions (tnsnames.ora) or provided as param
onSuccessExecute(context, dpiConn_create(context, oracleuser, oracleuser.len,
    pw, pw.len, connString, connString.len, commonParams.addr, nil, addr(conn))):
  echo "connection created"
  var prepStatement: ptr dpiStmt
  var numCols: uint32
  var numRows: uint64

  let query = "select 'hello nim! ' from dual ".cstring
  let scrollAble = 0.cint
  let tagLength = 0.uint32

  # simple select example
  onSuccessExecute(context, dpiConn_prepareStmt(conn, scrollAble, query,
      query.len.uint32, nil, tagLength,
            prepStatement.addr)):

    onSuccessExecute(context, dpiStmt_execute(prepStatement,
        DpiModeExec.DEFAULTMODE.ord, numCols.addr)):
      echo "num_cols_returned: " & $numCols
      # fetch the row to client
      var bufferRowIndex: uint32
      var found: cint

      onSuccessExecute(context, dpiStmt_fetch(prepStatement, found.addr,
          bufferRowIndex.addr)):
        # fetch one row
        var stringColVal: ptr dpiData
        var nativeTypeNum: dpiNativeTypeNum

        onSuccessExecute(context, dpiStmt_getQueryValue(prepStatement, 1,
            nativeTypeNum.addr, stringColVal.addr)):
          if stringColVal.isNull == 0:
            echo "encoding: " & $stringColVal.value.asBytes.encoding
            echo "colval: " & toNimString(stringColVal)

            var queryInfo: dpiQueryInfo

            onSuccessExecute(context, dpiStmt_getQueryInfo(prepStatement, 1,
                queryInfo.addr)):
              echo "dbtype: " & $DpiOracleTypes(
                  queryInfo.typeInfo.oracleTypeNum) &
                      " size_in_chars " & $queryInfo.typeInfo.sizeInChars

          else:
            echo "val_is_null"

          discard dpiStmt_getRowCount(prepStatement, numRows.addr)
          echo "prepStatement: num_rows_fetched: " & $numRows

    var prepStatement2: ptr dpiStmt

    onSuccessExecute(context,
                       dpiConn_prepareStmt(conn, scrollAble, testTypesSql,
                           testTypesSql.len.uint32,
                                           nil, tagLength, prepStatement2.addr)):
    # example fetching multiple rows
      onSuccessExecute(context, dpiStmt_execute(prepStatement2,
          DpiModeExec.DEFAULTMODE.ord, numCols.addr)):
        var colcount: uint32
        discard dpiStmt_getNumQueryColumns(prepStatement2, colcount.addr)
        echo "num_query_cols " & $colcount

        var colinfo: dpiQueryInfo
        var typeinfo: dpiDataTypeInfo

        #introspect resultset
        for i in countup(1, colcount.int):
          if dpiStmt_getQueryInfo(prepStatement2, i.uint32,
              colinfo.addr) < DpiResult.SUCCESS.ord:
            echo "error_introspect_column " & $i
          else:
            echo $DpiOracleTypes(colinfo.typeinfo.oracleTypeNum) &
                  " clientsize: " & $colinfo.typeinfo.clientSizeInBytes.uint32

        type
          ColArray = array[0..3, Column]
        var columns: ColArray
        # TODO: construct the dpiVars out of dpiQueryInfo
        newVar(conn, DpiOracleTypes.OTVARCHAR, DpiNativeCTypes.NativeBYTES,
            100, 10, columns[0].addr)
        if hasError(columns[0]):
          echo "error_newvar_col1"
        newVar(conn, DpiOracleTypes.OTNATIVE_DOUBLE,
            DpiNativeCTypes.NativeDOUBLE, 100, 1, columns[1].addr)
        if hasError(columns[1]):
          echo "error_newvar_col2"
        newVar(conn, DpiOracleTypes.OTRAW, DpiNativeCTypes.NativeBYTES, 100,
            10, columns[2].addr)
        if hasError(columns[2]):
          echo "error_newvar_col3"
        newVar(conn, DpiOracleTypes.OTTIMESTAMP_TZ,
            DpiNativeCTypes.NativeTIMESTAMP, 100, 1, columns[3].addr)
        if hasError(columns[3]):
          echo "error_newvar_col4"

        for i in low(columns) .. high(columns):
          if hasError(context, dpiStmt_define(prepStatement2, (i+1).uint32,
              columns[i].colVar)):
            var err: dpiErrorInfo
            dpiContext_getError(context, err.addr)
            break

        var moreRows: cint
        var bufferRowIndex: uint32
        var rowsFetched: uint32

        onSuccessExecute(context, dpiStmt_fetchRows(prepStatement2,
                                                   50.uint32,
                                                   bufferRowIndex.addr,
                                                   rowsFetched.addr,
                                                   moreRows.addr)):
          # fetchRows gives you a spreadsheet-like access to the resultset
          echo "prepStatement2: num_rows_fetched: " & $rowsFetched

          echo "col1: " & toNimString(columns[0].buffer)
          echo "col1: " & $dpiData_getDouble(columns[1].buffer)
          # remark: big numbers are exposed as client type: string (out of scope of this demo)
          echo "col2: " & toNimString(columns[0].buffer[1])
          echo "col2: " & $dpiData_getDouble(columns[1].buffer[1])
          # raw column
          echo "col3: " & toHex(toNimString(columns[2].buffer))
          echo "col3: " & toHex(toNimString(columns[2].buffer[1]))
          # tstamp column
          var tstamp: dpiTimestamp = cast[dpiTimestamp](columns[
              3].buffer.value.asTimestamp)
          echo "col4: " & $tstamp

          if isNull(columns[3].buffer[1]):
            echo "col4: col missing value "
          else:
            tstamp = cast[dpiTimestamp](columns[3].buffer[
                1].value.asTimestamp)
            echo "col4: " & $tstamp

        for i in low(columns) .. high(columns):
          discard dpiVar_release(columns[i].colVar)

    discard dpiStmt_release(prepStatement2)
  discard dpiStmt_release(prepStatement)

  # refCursors example taken out of DemoRefCursors.c
  echo "executing ref_cursor example "
  onSuccessExecute(context,
                   dpiConn_prepareStmt(conn, scrollAble, testRefCursor,
                       testRefCursor.len.uint32,
                                       nil, tagLength, prepStatement.addr)):

    var refCursorCol: Column

    newVar(conn, DpiOracleTypes.OTSTMT, DpiNativeCTypes.NATIVESTMT, 1, 0,
        refCursorCol.addr)
    if hasError(refCursorCol):
      echo "error_init_refcursor_column"

    if dpiStmt_bindByPos(prepStatement, 1,
        refCursorCol.colvar) < DpiResult.SUCCESS.ord:
      echo "error_binding_refcursor_param"

    onSuccessExecute(context, dpiStmt_execute(prepStatement,
        DpiModeExec.DEFAULTMODE.ord, numCols.addr)):
      discard dpiStmt_release(prepStatement)

      prepStatement = refCursorCol.buffer.value.asStmt # fetch ref_cursor

      # fetch cursor content
      var bufferRowIndex: uint32
      var found: cint
      var stringColVal: ptr dpiData
      var nativeTypeNum: dpiNativeTypeNum

      for i in countup(1, 2):
        onSuccessExecute(context,
                         dpiStmt_fetch(prepStatement, found.addr,
                             bufferRowIndex.addr)):
          if found != 1:
            break
          onSuccessExecute(context,
                            dpiStmt_getQueryValue(prepStatement, 1,
                                nativeTypeNum.addr, stringColVal.addr)):
            if stringColVal.isNull == 0:
              echo "encoding: " & $stringColVal.value.asBytes.encoding
              echo "ref_cursor_val: " & toNimString(stringColVal)
            else:
              echo "ref_cursor value is null"

      discard dpiVar_release(refCursorCol.colVar)

  discard dpiConn_release(conn)

# TODO: blob,execute pl/sql, execute script , utilize poolableConnection

discard dpiContext_destroy(context)
