import ../nimodpi
import strutils
import os
import times

# testsetup: win10,instantclient_19_3_x64
# target: 12.2.0.1 PDB and 12.1.0.2(exadata,1n)
# compiler: gcc version 5.1.0 (tdm64-1) 
# TODO: testing against timesten

#[
 this demo contains three examples (just select stmt - no ddl executed - statements
 can be found in demosql.nim )
   - setting clients encoding 
   - simple fetch
   - fetch with fetchRows (additional types double,raw,timestamp,big_number as string)
   - ref_cursor example 
]#

const
  nlsLang: cstring = "WE8ISO8859P15"

include democredentials
include demosql

proc `$`* (p: var dpiTimestamp): string =
  ## string representation of a timestamp column
  "dpiTimestamp: year:" & $p.year & " month:" & $p.month & " day:" & $p.day & 
    " hour: " & $p.hour & " minute:" & $p.minute & " second:" & $p.second & 
    " fsecond:" & $p.fsecond &
    " tzHOffset:" & $p.tzHourOffset & " tzMinOffset:" & $p.tzMinuteOffset

proc toDateTime(p : ptr dpiTimestamp ) : DateTime =
  ## dpiTimestamp to DateTime
  let utcoffset : int = p.tzHourOffset*3600.int + p.tzMinuteOffset*60 
  proc utcTzInfo(time: Time): ZonedTime =
    ZonedTime(utcOffset: utcoffset, isDst: false, time: time)
  initDateTime(p.day,Month(p.month),p.year,p.hour,p.minute,p.second,p.fsecond, 
    newTimezone("Etc/UTC", utcTzInfo, utcTzInfo))

proc `$`*(p: var dpiStmtInfo): string =
  ## string repr of a statementInfo obj
  "dpiStatementInfo: isQuery " & $p.isQuery & " isPlSql: " & $p.isPLSQL &
    " isDDL: " & $p.isDDL & " isDML: " & $p.isDML & " isReturning: " &
        $p.isReturning &
      " " & $DpiStmtType(p.statementType)


template `[]`(data: ptr dpiData, idx: int): ptr dpiData =
  ## accesses the cell(row) of the column by index
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
  ColumnBuffer = object
    colVar: ptr dpiVar
    buffer: ptr dpiData
    dpiresult: DpiResult      # contains errorcode and msg

type
  PreparedStatement = object
    nativeStatement: ptr dpiStmt
    statementInfo: dpiStmtInfo
    # obj from int dpiStmt_getInfo(dpiStmt *stmt, dpiStmtInfo *info
    columnDataTypes: seq[dpiQueryInfo]
    columnBuffers: seq[ColumnBuffer]
    fetchArraySize: uint32
    columnCount: uint32

template `[]`(pstmt: var PreparedStatement, idx: int): ptr dpiData =
  ## access the columnBuffer by index
  pstmt.columnBuffers[idx].buffer

proc `$`*(p: var PreparedStatement): string =
  "preparedStmt: colcount: " & $p.columnCount & " " & $p.columnDataTypes

template newVar(conn: ptr dpiConn, otype: DpiOracleTypes,
    ntype: DpiNativeCTypes, arrSize: int, colLength: uint32,
                column: ptr ColumnBuffer) =
  ## initialises a new dpiVar and populates the ColumnBuffer-type
  column.dpiresult = DpiResult(dpiConn_newVar(conn, cast[dpiOracleTypeNum](
      otype.ord), # db coltype
    cast[dpiNativeTypeNum](ntype.ord), # client coltype
    arrSize.uint32, # max array size
    colLength, # size of buffer
    0, # sizeIsBytes
    0, # isArray
    nil, # objType
    column.colVar.addr, # ptr to the variable
    column.buffer.addr        # ptr to buffer array
  ))

template releaseBuffer(prepStmt: var PreparedStatement) =
  ## releases the internal buffers. to reinit initMetadataAndAllocBuffersAfterExecute must
  ## be used
  for i in countup(0, prepStmt.columnBuffers.len-1):
    discard dpiVar_release(prepStmt.columnBuffers[i].colVar)


template initMetadataAndAllocBuffersAfterExecute(ctx: ptr dpiContext,
    conn: ptr dpiConn, prepStmt: var PreparedStatement) =
  ## fetches the statements metadata after execute. 
  ## if the statement returns any rows the internal buffer
  ## is initialised according to the internal fetchArraySize. 
  ## TODO: handle refcursor differently 
  ## (we can not introspect the refcursor till it's fetched)
  ## TODO: if numeric exceeds 64bit handle as string
  discard dpiStmt_getFetchArraySize(prepStmt.nativeStatement,
      prepStmt.fetchArraySize.addr)
  discard dpiStmt_getNumQueryColumns(prepStmt.nativeStatement,
      prepStmt.columnCount.addr)
  if dpiStmt_getInfo(prepstatement.nativeStatement,
      prepStmt.statementInfo.addr) == DpiResult.SUCCESS.ord:
    echo $prepStmt.statementInfo
    if prepStmt.statementInfo.isQuery == 1.cint:
      prepStmt.columnDataTypes = newSeq[dpiQueryInfo](prepStmt.columnCount)
      prepStmt.columnBuffers = newSeq[ColumnBuffer](prepStmt.columnCount)

      var colinfo: dpiQueryInfo

      #introspect resultset
      for i in countup(1, prepStmt.columnCount.int):
        if dpiStmt_getQueryInfo(prepStmt.nativeStatement, i.uint32,
            colinfo.addr) < DpiResult.SUCCESS.ord:
          echo "error_introspect_column " & $i
        else:
          prepStmt.columnDataTypes[i-1] = colinfo
          echo $DpiOracleTypes(colinfo.typeinfo.oracleTypeNum) &
            " clientsize: " & $colinfo.typeinfo.clientSizeInBytes.uint32

      for i in countup(0, prepStmt.columnDataTypes.len-1):
        var cbuf: ColumnBuffer
        let otype = DpiOracleTypes(prepStmt.columnDataTypes[
            i].typeInfo.oracleTypeNum)
        let ntype = DpiNativeCTypes(prepStmt.columnDataTypes[
            i].typeInfo.defaultNativeTypeNum)
        echo $otype & " " & $ntype
        echo "oci_type_code " & $prepStmt.columnDataTypes[i].typeInfo.ociTypeCode
          # TODO: construct the dpiVars out of dpiQueryInfo
        var size: uint32
        case ntype
          of NativeINT64, NativeUINT64, NativeFLOAT, NativeDouble,
              NativeTIMESTAMP, NativeINTERVAL_DS,
             NativeINTERVAL_YM, NativeBOOLEAN, NativeROWID:
            size = 1
            echo "scale: " & $prepStmt.columnDataTypes[i].typeInfo.scale
            echo " precision : " & $prepStmt.columnDataTypes[
                i].typeInfo.precision
          of NativeBYTES:
            size = prepStmt.columnDataTypes[i].typeInfo.sizeInChars
            if size == 0:
              # non character data
              size = prepStmt.columnDataTypes[i].typeInfo.clientSizeInBytes
          else:
            echo "unsupportedType at idx: " & $i
            # TODO: proper error handling
            break
        if i == 4: # bignum column
          echo "size_col_4 chars " & $prepStmt.columnDataTypes[i].typeInfo.sizeInChars
          echo "size_col_4 clientsize " & $prepStmt.columnDataTypes[i].typeInfo.clientSizeInBytes
          echo "size_col_4 dbsize " & $prepStmt.columnDataTypes[i].typeInfo.dbSizeInBytes
          # these values are only populated if varchar2 type. introspection is limited here
          # and it´s not possible to detect big numbers
          newVar(conn, otype, DpiNativeCTypes.NativeBYTES,
              (prepStmt.fetchArraySize).int,1, cbuf.addr)
        else:
          newVar(conn, otype, ntype, (prepStmt.fetchArraySize).int, size,
              cbuf.addr)
        # TODO remove template newVar
        if hasError(cbuf):
          echo "error_newvar at column: " & $(i+1)
          break
        else:
          prepStmt.columnBuffers[i] = cbuf

      for i in countup(0, prepStmt.columnBuffers.len-1):
        # bind buffer to statement
        if dpiStmt_define(prepStmt.nativeStatement, (i+1).uint32,
             prepStmt.columnBuffers[i].colVar) == DpiResult.FAILURE.ord:
          var err: dpiErrorInfo
          dpiContext_getError(ctx, err.addr)
          echo $err
          break

template isNull(dat: ptr dpiData): bool =
  if dat.isNull == 1.cint:
    true
  else:
    false

template hasError(colvar: var ColumnBuffer): bool =
  if colvar.dpiresult < DpiResult.SUCCESS:
    true
  else:
    false

template hasError(context: ptr dpiContext, toprobe: untyped): bool =
  if toprobe < DpiResult.SUCCESS.ord:
    true
  else:
    false

var context: ptr dpiContext
var errorinfo: dpiErrorInfo
var versionInfo: dpiVersionInfo
var commonParams: dpiCommonCreateParams
var connectionParams : dpiConnCreateParams
# globals

let errno = dpiContext_create(DPI_MAJOR_VERSION, DPI_MINOR_VERSION, addr(
    context), addr(errorinfo))
if errno == DpiResult.SUCCESS.ord:
  echo "context_created"
  discard dpiContext_initCommonCreateParams(context, commonParams.addr)
  discard dpiContext_initConnCreateParams(context,connectionParams.addr)
  connectionParams.authMode = DpiAuthMode.SYSDBA.ord
  commonParams.encoding = nlsLang
else:
  echo "unable to create context: " & $errorinfo

discard dpiContext_getClientVersion(context, addr(versionInfo))
echo "client_version: " & $versionInfo.versionNum

var conn: ptr dpiConn

# connectionstrings could be from tns definitions (tnsnames.ora) or provided as param
onSuccessExecute(context, dpiConn_create(context, oracleuser, oracleuser.len,
    pw, pw.len, connString, connString.len, commonParams.addr,connectionParams.addr, addr(conn))):
  echo "connection created"
  
  var prepStatement: ptr dpiStmt
  var numCols: uint32
  var numRows: uint64

  let query = "select 'hello äöü ' from dual ".cstring
  let nlsQuery  = "ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '. ' ".cstring
  let scrollAble = 0.cint
  let tagLength = 0.uint32

  onSuccessExecute(context, dpiConn_prepareStmt(conn, scrollAble,nlsQuery,
      nlsQuery.len.uint32, nil, tagLength,
            prepStatement.addr)):
   
    onSuccessExecute(context, dpiStmt_execute(prepStatement,
        DpiModeExec.DEFAULTMODE.ord, numCols.addr)): 
      discard     
  discard dpiStmt_release(prepStatement)

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
      #eval fetch_array_size
      var arrSize: uint32
      discard dpiStmt_getFetchArraySize(prepStatement2, arrSize.addr)
      echo "fetch_array_size: " & $arrSize
      # int dpiStmt_setFetchArraySize(dpiStmt *stmt, uint32_t arraySize)
      # example fetching multiple rows
      # metadata can be retrieved with dpiStmt_getQueryInfo() after execute.
      onSuccessExecute(context, dpiStmt_execute(prepStatement2,
          DpiModeExec.DEFAULTMODE.ord, numCols.addr)):

        var prepStatement: PreparedStatement
        prepStatement.nativeStatement = prepStatement2

        initMetadataAndAllocBuffersAfterExecute(context, conn, prepstatement)
        echo "num_query_cols " & $prepStatement.columnCount

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

          echo "col1: " & toNimString(prepStatement[0][0]) # column/row
          echo "col2: " & $dpiData_getDouble(prepStatement[1][0])
          echo "col1: " & toNimString(prepStatement[0][1])
          echo "col2: " & $dpiData_getDouble(prepStatement[1][1])
          # raw column
          echo "col3: " & toHex(toNimString(prepStatement[2][0]))
          echo "col3: " & toHex(toNimString(prepStatement[2][1]))

          # tstamp column
          let tstamp: ptr dpiTimestamp = cast[ptr dpiTimestamp](prepStatement[3][
              0].value.asTimestamp.addr)
          echo " dateTime : " & $toDateTime(tstamp)

          if isNull(prepStatement[3][1]):
            echo "col4: col missing value "
          else:
            var tstamp2 : ptr dpiTimestamp = cast[ptr dpiTimestamp](prepStatement[3][1].value.asTimestamp.addr)
            echo "col4: " & $toDateTime(tstamp2)
          echo "col5: " & toNimString(prepStatement[4][0])
          echo "col5: " & toNimString(prepStatement[4][1])
          # output big_numbers as string
          # TODO: probe if it's a big_number

        releaseBuffer(prepStatement)

    discard dpiStmt_release(prepStatement2)
  discard dpiStmt_release(prepStatement)

  # refCursors example taken out of DemoRefCursors.c
  echo "executing ref_cursor example "
  onSuccessExecute(context,
                   dpiConn_prepareStmt(conn, scrollAble, testRefCursor,
                       testRefCursor.len.uint32,
                                       nil, tagLength, prepStatement.addr)):

    var refCursorCol: ColumnBuffer

    newVar(conn, DpiOracleTypes.OTSTMT, DpiNativeCTypes.NATIVESTMT, 1, 0,
        refCursorCol.addr)
    if hasError(refCursorCol):
      echo "error_init_refcursor_column"

    if dpiStmt_bindByPos(prepStatement, 1,
        refCursorCol.colvar) < DpiResult.SUCCESS.ord:
      echo "error_binding_refcursor_param"

    onSuccessExecute(context, dpiStmt_execute(prepStatement,
        DpiModeExec.DEFAULTMODE.ord, numCols.addr)):
      # introspect refCursor
      var colcount: uint32
      discard dpiStmt_getNumQueryColumns(prepStatement, colcount.addr)
      echo "refcursor: num_query_cols " & $colcount
      var colinfo: dpiQueryInfo
      var typeinfo: dpiDataTypeInfo
      var statementInfo: dpiStmtInfo
      if dpiStmt_getInfo(prepStatement, statementInfo.addr) ==
          DpiResult.SUCCESS.ord:
        echo $statementInfo

      #introspect resultset
      for i in countup(1, colcount.int):
        if dpiStmt_getQueryInfo(prepStatement, i.uint32,
            colinfo.addr) < DpiResult.SUCCESS.ord:
          echo "error_introspect_column " & $i
        else:
          echo $DpiOracleTypes(colinfo.typeinfo.oracleTypeNum) &
            " clientsize: " & $colinfo.typeinfo.clientSizeInBytes.uint32
      # a refcursor could not be introspected by the statementInfo 
      # -> we need the metadata (refcursor) from the caller
      # TODO: in this case the refcursor is opened by the client
      # - but a procedure could also return a refCursor (is ref_cursor)
      # example needed
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


