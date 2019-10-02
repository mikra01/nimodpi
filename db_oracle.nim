import nimodpi
import os
import times
import typeinfo
# import result unused at the moment

#[
  nim oracle database access layer. this is the high level API.

    - native proc names preserved for easier linkage to the odpi-c docs
    - new experimental API with exposed original ODPI-C api.
    -
    - this API is far away from being perfect. the design goal is to provide
    - a simple, easy to use API without thinking about internals and without
    - implementation quirks.
    -
    - some features:
    - resultset zero-copy approach: the caller is responsible for copying (helper templates present)
    - within the application domain. "peeking" data is possible via pointers
    - only the basic types are implemented (number, blob, rowid, varchar2, timestamp)
    - pl/sql procedure exploitation is possible with in/out and inout-parameters
    - consuming refcursor is also possible (see demo.nim)
    -
    - designing a vendor generic database API often leads to clumpsy workaround solutions.
      due to that it's out of scope of this project. it's more valueable to wrap the vendor
      specific parts into a own module with a question/answer style API according to the business-case
    -
    - besides the connections there are three basic important objects:
    - ParamType is used for parameter binding (in/out/inout) and consuming result columns
    - PreparedStatement is used for executing dml/ddl with or without parameters. internal resources
    - are not freed unless destroy is called.
    -
    - ResultSets are used to consume query results and can be reused. it provides a row-iterator-style
    - API and a direct access API of the buffer (by index)
    -
    - some additional hints: do not share connection/preparedStatement between different threads. 
    - the context
    - can be shared between threads according to the ODPI-C documentation (untested)
    - index-access of a resultset is not bounds checked
    - if a internal error happens, execution is terminated and the cause could be extracted with the
    - template getErrstr out of the context.
    - the API does not prevent you from misuse. 
    -
    - for testing and development the XE database is sufficient.
    - version 18c also supports partitioning, PDB's and so on.
    -
    - database resident connection pool is not tested but should work
    -
    - TODO: more types, implement tooling for easier sqlplus exploitaition,
    - tooling for easy compiletime-query validation, examples
    -
  ]#

type
  OracleContext* = object
    ## wrapper for the context and createParams
    oracleContext: ptr dpiContext
    versionInfo: dpiVersionInfo
    commonParams: dpiCommonCreateParams
    connectionParams: dpiConnCreateParams

  NlsLang* = distinct string

  OracleConnection* = object
    ## wrapper only at the moment
    connection: ptr dpiConn
    context: OracleContext

  BindRefType* = enum byPosition, byName

  BindRef = object
    # we need to track the bindType.
    # OUT/INOUT vars must be freed by the code -
    # IN vars are processed automatically
    # by the odpi-c layer
    case kind*: BindRefType
      of byPosition: paramVal*: int
      of byName: paramName*: cstring

  ParamType* = object
    ## describes how the database type is mapped onto
    ## the database type.
    bindPosition*: BindRef
    queryInfo: dpiQueryInfo
    # position of the parameter
    nativeType*: DpiNativeCTypes
    dbType*: DpiOracleTypes
    scale*: int
    ## only for numeric types
    size*: int
    paramVar: ptr dpiVar
    buffer: ptr dpiData
    # columnBuffer* : ColumnBuffer
    columnBufferSize: int
    ## for single parameters always 1 - for columnar parameters > 1 up to
    ## the given arraySize

  ParamList = seq[ParamType]

  # use dpiStmt_executeMany for bulk binds

  SqlQuery* = object
    ## fixme: use sqlquery from db_common
    rawSql: cstring

  PreparedStatement* = object
    relatedConn: OracleConnection
    query*: SqlQuery
    boundParams: ParamList      # mixed in/out or columnar
    stmtCacheKey*: cstring
    scrollable: bool            # unused
    executed: bool              # quirky flag used to track the state
    columnCount: uint32         # deprecated
                                # fetchArraySize : int
    pStmt: ptr dpiStmt
    statementInfo*: dpiStmtInfo # populated within execute stage
                                # following members are resultset related
    rsOutputCols: ParamList
    rsCurrRow*: int             # reserved for iterating
    rsMoreRows*: bool           #
    rsBufferRowIndex*: int
    rsRowsFetched*: int
    rsBufferedRows*: int        # refers to the maxArraySize
    rsColumnNames*: seq[string] # todo: implement

  ResultSet* = PreparedStatement

  DpiRow* = seq[ptr dpiData]

include odpi_obj2string
include odpi_to_nimtype

template `[]`(data: ptr dpiData, idx: int): ptr dpiData =
  ## accesses the cell(row) of the columnbuffer by index
  cast[ptr dpiData]((cast[int](data)) + (sizeof(dpiData)*idx))

template `[]`(rs: var ResultSet, colidx: int): ParamType =
  ## selects the column of the resultSet.
  rs.rsOutputCols[colidx]

template `[]`(rs: var ParamType, rowidx: int): ptr dpiData =
  ## selects the row of the specified column
  ## the value could be extracted by the dpiData/dpiDataBuffer API
  ## or with the fetch-templates (WIP)
  ##
  ## further reading:
  ## https://oracle.github.io/odpi/doc/structs/dpiData.html
  cast[ptr dpiData]((cast[int](rs.buffer)) + (sizeof(dpiData)*rowidx))

template nativeType*(pt: var ParamType): DpiNativeCTypes =
  ## peeks the native type of a param. useful to determine
  ## which type the result column would be
  pt.nativeType

template dbType*(pt: var ParamType): DpiOracleTypes =
  ## peeks the db type of the param. usefull to determine
  ## which type the result column would be
  pt.dbType

template newParamList(len: int): ParamList =
  newSeq[ParamType](len)

proc newSqlQuery*(sql: string): SqlQuery =
  SqlQuery(rawSql: sql.cstring)

proc newOracleContext*(encoding: NlsLang, authMode: DpiAuthMode,
                       outCtx: var OracleContext,
                           outMsg: var string): DpiResult =
  ## constructs a new OracleContext needed to access the database.
  ## if DpiResult.SUCCESS is returned the outCtx is populated. if not the outMsg
  ## contains the error message.
  var ei: dpiErrorInfo
  result = DpiResult(
       dpiContext_create(DPI_MAJOR_VERSION, DPI_MINOR_VERSION, addr(
       outCtx.oracleContext), ei.addr)
    )
  if result == DpiResult.SUCCESS:
    discard dpiContext_initCommonCreateParams(outCtx.oracleContext,
        outCtx.commonParams.addr)
    discard dpiContext_initConnCreateParams(outCtx.oracleContext,
        outCtx.connectionParams.addr)
    outCtx.connectionParams.authMode = authMode.ord.uint32
    outCtx.commonParams.encoding = encoding.cstring
  else:
    outMsg = $ei

proc destroyOracleContext*(ocontext: var OracleContext): DpiResult =
  ## destroys the present oracle context. the resultcode of this operation could
  ## be checked with hasError
  # TODO: evaluate what happens if there are open connection present
  result = DpiResult(dpiContext_destroy(ocontext.oracleContext))

template getErrstr*(ocontext: var OracleContext): string =
  ## checks if the last operation results with error or not
  var ei: dpiErrorInfo
  dpiContext_getError(octx.oracleContext, ei.addr)
  $ei

template isSuccess*(result: DpiResult): bool =
  result == DpiResult.SUCCESS

template onSuccessExecute(context: ptr dpiContext, toprobe: untyped,
    body: untyped) =
  ## template to wrap the boilerplate errorinfo code for testing purposes
  var err: dpiErrorInfo
  if toprobe < DpiResult.SUCCESS.ord:
    dpiContext_getError(context, err.addr)
    echo $err
  else:
    body

template isExecuted*(ps: var PreparedStatement): bool =
  ## true if the statement was executed
  ps.executed


proc createConnection*(octx: var OracleContext,
                         connectstring: string,
                         username: string,
                         passwd: string,
                             ocOut: var OracleConnection): DpiResult =
  ## creates a connection for the given context and credentials. use getErrstr to retrieve
  ## the error message in case of failure
  ocOut.context = octx
  result = DpiResult(dpiConn_create(octx.oracleContext, username.cstring,
    username.cstring.len.uint32,
    passwd.cstring, passwd.cstring.len.uint32, connectstring,
    connectstring.len.uint32,
    octx.commonParams.addr, octx.connectionParams.addr, addr(ocOut.connection)))

proc releaseConnection*(conn: var OracleConnection): DpiResult =
  ## releases the connection
  result = DpiResult(dpiConn_release(conn.connection))

proc newPreparedStatement*(conn: var OracleConnection, query: var SqlQuery,
                           outPs: var PreparedStatement,
                               stmtCacheKey: string = ""): DpiResult =
  ## constructs a new prepared statement object linked to the given specified query.
  ## the statement cache key is optional
  outPs.scrollable = false # always false due to not implemented
  outPs.query = query
  outPs.columnCount = 0
  outPs.relatedConn = conn
  outPs.executed = false
  outPs.stmtCacheKey = stmtCacheKey.cstring
  #outPs.rsOutputCols = newSeq[ParamType](1)
  #outPs.boundParams = newSeq[ParamType](1)
  result = DpiResult(dpiConn_prepareStmt(conn.connection, 0.cint, query.rawSql,
      query.rawSql.len.uint32, outPs.stmtCacheKey,
      outPs.stmtCacheKey.len.uint32, outPs.pStmt.addr))

template bindParameter(ps: var PreparedStatement, param: var ParamType,
    size: int, sizeIsBytes: int) =
  ## internal proc which is processed after the param is completely populated
  var isArray: uint32 = 0
  if ps.rsBufferedRows > 1:
    isArray = 1
  discard
    dpiConn_newVar(
         ps.relatedConn.connection,
         cast[dpiOracleTypeNum](param.dbType.ord),
         cast[dpiNativeTypeNum](param.nativeType.ord),
         ps.rsBufferedRows.uint32, #maxArraySize
      size.uint32, #size
      sizeIsBytes.cint, #sizeIsBytes
      isArray.cint, # isArray
      nil,
      param.paramVar.addr,
      param.buffer.addr
      )

  if param.bindPosition.kind == BindRefType.byPosition:
    discard DpiResult(dpiStmt_bindByPos(ps.pStmt,
                                         param.bindPosition.paramVal.uint32,
                                         param.paramVar
      )
    )
  elif param.bindPosition.kind == BindRefType.byName:
    discard DpiResult(dpiStmt_bindByName(ps.pStmt,
                                         param.bindPosition.paramName,
                                         param.bindPosition.paramName.len.uint32,
                                         param.paramVar
      )
    )

proc exploreSize(param: var ParamType, outSize: var int,
    outSizeIsBytes: var int) =
  ## fetches the size of bytes according to the type
  # FIXME: deprecated
  outSize = 1
  outSizeIsBytes = 0
  case param.dbType
    of DpiOracleTypes.OTVARCHAR, OTNVARCHAR, OTCHAR, OTNCHAR, OTCLOB, OTNCLOB, OTLONG_VARCHAR:
    # new dpi var for byte-types (for instance varchar2, blob )
      outSize = param.size
    of OTRAW, OTBLOB, OTLONG_RAW:
      outSizeIsBytes = 1
    of OTNONE, OTROWID, OTNATIVE_FLOAT, OTNATIVE_DOUBLE, OTNATIVE_INT,
       OTNUMBER, OTDATE, OTTIMESTAMP, OTTIMESTAMP_TZ, OTTIMESTAMP_LTZ,
       OTINTERVAL_DS, OTINTERVAL_YM, OTBFILE, OTSTMT, OTBOOLEAN,
       OTOBJECT, OTNATIVE_UINT, OTMAX:
      discard


proc bindParameter(ps: var PreparedStatement, param: var ParamType) =
  ## before calling BindRef and columnBufferSize must be initialised by the caller.
  ## TODO: implement
  var size: int = 0
  var sizeIsBytes: int = 0
  exploreSize(param, size, sizeIsBytes)
  # fixme: introduce error handling philosophy
  bindParameter(ps, param, size, sizeIsBytes)

# FIXME: templates for setting up std params

# use dpiStmt_fetch/fetch_rows,execute,executeMany
proc bindParameters(ps: var PreparedStatement, paramList: var ParamList) =
  ## binds in, out or inout parameters to this prepared statement.
  ## the internal structures are retained till this preparedStatement is recycled
  for i in paramList.low .. paramList.high:
    bindParameter(ps, paramList[i])

proc addOutColumn(rs: var ResultSet, columnParam: var ParamType) =
  ## binds out-parameters to the specified resultset according to the
  ## metadata given by the database
  var isArray: uint32 = 0
  let index: int = columnParam.bindPosition.paramVal-1
  # adjust index to nimIndex
  if rs.rsBufferedRows > 1:
    isArray = 1
  rs.rsOutputCols[index] = columnParam

  var paramVar: ptr dpiVar
  var paramBuff: ptr dpiData
  discard DpiResult(
      dpiConn_newVar(
         rs.relatedConn.connection,
         cast[dpiOracleTypeNum](rs.rsOutputCols[index].dbType.ord),
         cast[dpiNativeTypeNum](rs.rsOutputCols[index].nativeType.ord),
         rs.rsBufferedRows.uint32, #maxArraySize
    columnParam.size.uint32, #size]
    0.cint, #sizeIsBytes
    isArray.cint, # isArray
    nil,
    paramVar.addr,
    paramBuff.addr
    )
  )
  discard dpiStmt_define(rs.pStmt, (index+1).uint32, paramVar)
  # dpiStmt_define is required - without the buffer is not populated
  columnParam.paramVar = paramVar
  columnParam.buffer = paramBuff


proc destroy*(prepStmt: var PreparedStatement) =
  ## frees the internal resources. this should be called if
  ## the prepared statement is no longer in use.
  ## additional resources of a present resultSet
  ## are also freed
  # resultSet present? -> dispose dpiVars
  # bind-parameters present? -> dispose dpiVars

  for i in prepStmt.boundParams.low .. prepStmt.boundParams.high:
    discard dpiVar_release(prepStmt.boundParams[i].paramVar)
  for i in prepStmt.rsOutputCols.low .. prepStmt.rsOutputCols.high:
    discard dpiVar_release(prepStmt.rsOutputCols[i].paramVar)

  discard dpiStmt_release(prepStmt.pStmt)

proc reset(rs: var ResultSet) =
  ## resets the resultset ready for re-execution (wind-back)
  # todo: implement
  discard

proc executeStatement*(prepStmt: var PreparedStatement,
                        outRs: var ResultSet,
                        fetchArraySize: int, # number of rows per column
                        dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord): DpiResult =
  ## executes the statement without internal buffer. the results can be fetched
  ## on a col by col base. once executed the bound columns could be reused
  ##
  ## multiple dpiMode's can be "or"ed together
  if not prepStmt.isExecuted:
    # TODO: reset() needed
    prepStmt.rsMoreRows = true
    prepStmt.rsRowsFetched = 0
    discard dpiStmt_setFetchArraySize(prepStmt.pStmt, fetchArraySize.uint32)
    # sets the given number of rows per column

    prepStmt.rsBufferedRows = fetchArraySize
    result = DpiResult(dpiStmt_execute(prepStmt.pStmt,
                                       dpiMode,
                                       prepStmt.columnCount.addr
      )
    )
    outRs = cast[ResultSet](prepStmt)
    if result == DpiResult.SUCCESS:
      if prepStmt.rsOutputCols.len <= 0:
        outRs.rsOutputCols = newParamList(prepStmt.columnCount.int)
        outRs.rsColumnNames = newSeq[string](prepStmt.columnCount.int)
        discard dpiStmt_getInfo(prepStmt.pStmt, prepStmt.statementInfo.addr)
        var qInfo: dpiQueryInfo

        for i in countup(1, prepStmt.columnCount.int):
          # construct needed params out of the metadata
          # the columnindex starts with 1
          # TODO: if a type is not supported by ODPI-C log error within the ParamType
          discard dpiStmt_getQueryInfo(prepStmt.pStmt, i.uint32, qInfo.addr)
          var colname = newString(qInfo.nameLength)
          copyMem(addr(colname[0]), qInfo.name.ptr, colname.len)

          outRs.rsColumnNames[i-1] = colname
          outRs.rsOutputCols[i-1] = ParamType(
                              bindPosition: BindRef(kind: BindRefType.byPosition,
                                                   paramVal: i),
                              queryInfo: qInfo,
                              nativeType: DpiNativeCTypes(
                                  qinfo.typeinfo.defaultNativeTypeNum),
                              dbType: DpiOracleTypes(
                                  qinfo.typeinfo.oracleTypeNum),
                              scale: qinfo.typeinfo.scale,
                              size: qinfo.typeinfo.clientSizeInBytes.int,
                              paramVar: nil,
                              buffer: nil,
                              columnBufferSize: outRs.rsBufferedRows)
          addOutColumn(outRs, outRs.rsOutputCols[i-1])
  else:
    result = DpiResult(DpiResult.FAILURE.ord)

proc fetchNextRows*(rs: var ResultSet): DpiResult =
  ## fetches next rows (if present) into the internal buffer
  ## if DpiResult.FAILURE is returned the internal error could be retrieved
  ## by calling getErrstr on the context.
  ##
  ## After fetching the window can be accessed by using the
  ## "[<colidx>][<rowidx>]" operator. No bounds check is performed.
  ## the colidx should not exceed the maximum column-cound and the
  ## rowidx should not exceed the given bufferRowIndex.
  ##
  ## remark: no data-copy is performed.
  ## blobs and strings (pointer types) should be copied into the application
  ## domain before calling fetchNextRows again.
  result = DpiResult.SUCCESS
  if rs.rsMoreRows:
    var moreRows: cint # out
    var bufferRowIndex: uint32 # out
    var rowsFetched: uint32 #out

    result = DpiResult(dpiStmt_fetchRows(rs.pStmt,
                                       rs.rsBufferedRows.uint32,
                                       bufferRowIndex.addr,
                                       rowsFetched.addr,
                                       moreRows.addr))
    if result == DpiResult.SUCCESS:
      rs.rsMoreRows = moreRows.bool
      rs.rsBufferRowIndex = bufferRowIndex.int
      rs.rsRowsFetched = rowsFetched.int


iterator resultSetRowIterator*(rs: var ResultSet): DpiRow =
  ## iterates over the resultset row by row. no data copy is performed
  ## and the ptr type values should be copiet into the application
  ## domain before the next window is requested
  var p: DpiRow = newSeq[ptr dpiData](rs.rsOutputCols.len)
  rs.rsCurrRow = 0

  if rs.rsRowsFetched == 0:
    discard fetchNextRows(rs) # todo: impl errorhandling
  while rs.rsCurrRow < rs.rsRowsFetched:
    for i in rs.rsOutputCols.low .. rs.rsOutputCols.high:
      p[i] = rs.rsOutputCols[i][rs.rsCurrRow]
      # construct column
    yield p
    inc rs.rsCurrRow
    if rs.rsCurrRow == rs.rsRowsFetched and rs.rsMoreRows:
      discard fetchNextRows(rs)
      rs.rsCurrRow = 0


when isMainModule:
  const
    lang: NlsLang = "WE8ISO8859P15".NlsLang
    oracleuser: string = "sys"
    pw: string = "<passwd>"
    connectionstr: string = """(DESCRIPTION = (ADDRESS = 
                             (PROTOCOL = TCP)
                             (HOST = <hostname>)  
                             (PORT = 1521))
                             (CONNECT_DATA =(SERVER = DEDICATED)
                             (SERVICE_NAME = XEPDB1 )
                            ))"""

  var octx: OracleContext
  var errmsg: string

  if isSuccess(newOracleContext(lang, DpiAuthMode.SYSDBA, octx, errmsg)):

    var conn: OracleConnection

    if isSuccess(createConnection(octx, connectionstr, oracleuser, pw, conn)):

      var query: SqlQuery = newSqlQuery("""select 100 as col1, 'äöü' as col2 from dual 
          union all 
          select 200 , 'äöü2' from dual
          union all
          select 300 , 'äöü3' from dual
          """)

      var pstmt: PreparedStatement

      if isSuccess(newPreparedStatement(conn, query, pstmt)):
        var rs: ResultSet

        if isSuccess(executeStatement(pstmt, rs, 2)):
          echo "type_column1 " & $nativeType(rs[0])
          echo "type_column2 " & $nativeType(rs[1])
          # TODO: generic variable fetching
          echo rs.rsColumnNames[0] & " " & rs.rsColumnNames[1]

          for row in resultSetRowIterator(rs): # todo: add type-metadata
            # column1 double column2 string
            echo $row[0].value.asDouble & " " & toNimString(row[1])
        
          pstmt.destroy

        else:
          echo getErrstr(octx)
      else:
        echo getErrstr(octx)

      discard conn.releaseConnection
    else:
      echo getErrstr(octx)

    discard destroyOracleContext(octx)

  else:
    echo errmsg

