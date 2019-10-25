import os
import times
import options
import strformat
import nimodpi

# Copyright (c) 2019 Michael Krauter
# MIT-license - please see the LICENSE-file for details.

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
    - resultset zero-copy approach: the caller is responsible
    - for copying the data (helper templates present)
    - within the application domain. "peeking" data is possible via pointers
    - only the basic types are implemented (numeric, rowid, varchar2, timestamp)
    - pl/sql procedure exploitation is possible with in/out and inout-parameters
    - consuming refcursor is also possible (see examples at the end of the file)
    - TODO: implement LOB/BLOB handling
    -
    - designing a vendor generic database API often leads to
      clumpsy workaround solutions.
      due to that a generic API is out of scope of this project.
      it's more valueable to wrap the vendor
      specific parts into a own module with a
      question/answer style API according to the business-case
    -
    - besides the connections there are three basic important objects:
    - ParamType is used for parameter binding (in/out/inout)
      and consuming result columns
    - PreparedStatement is used for executing dml/ddl with or
      without parameters. internal resources
      are not freed unless destroy is called.
    - ResultSets are used to consume query results and can be reused.
    - it provides a row-iterator-style
    - API and a direct access API of the buffer (by index)
    -
    - some additional hints: do not share connection/preparedStatement
      between different threads.
    - the context can be shared between threads according to the
      ODPI-C documentation (untested).
    - index-access of a resultset is not bounds checked.
    - if a internal error happens, execution is terminated
      and the cause could be extracted with the
    - template getErrstr out of the context.
    -
    - for testing and development the XE database is sufficient.
    - version 18c also supports partitioning, PDB's and so on.
    -
    - database resident connection pool is not tested but should work
    -
    - TODO: more types,bulk binds, implement tooling for
      easier sqlplus exploitaition,
    - tooling for easy compiletime-query validation,
      continous query notification, examples

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

  BindIdx = distinct range[1.int .. int.high]

  BindInfoType = enum byPosition, byName

  BindInfo = object
    # tracks the bindType.
    case kind*: BindInfoType
      of byPosition: paramVal*: BindIdx
      of byName: paramName*: string

  ParamType* = object
    ## describes how the database type is mapped onto
    ## the query
    bindPosition*: BindInfo
    # bind position and type -> rename 2 bindinfo
    queryInfo: dpiQueryInfo
    # populated for returning statements
    columnType*: ColumnType
    # tracks the native- and dbtype
    paramVar: ptr dpiVar
    # ODPI-C ptr to the variable def
    buffer: ptr dpiData
    # ODPI-C ptr to the data buffer
    rowBufferSize: int
    isPlSqlArray: bool
    isFetched: bool
    # flag used for refcursor reexecute prevention.
    # if a refcursor is within the statement it can't be reused

  ParamTypeRef* = ref ParamType
    ## handle to the param type

  ParamTypeList* = seq[ParamTypeRef]

  ColumnType* = tuple[nativeType: DpiNativeCType,
                      dbType: DpiOracleType,
                      colsize: int,
                      sizeIsBytes: bool,
                      scale: int] # scale used for some numeric types
  ColumnTypeList* = seq[ColumnType]
  # predefined column types

const
  RefCursorColumnTypeParam* = (DpiNativeCType.STMT,
                               DpiOracleType.OTSTMT,
                               1, false, 1)
  ## predefined parameter for refcursor                                 
  Int64ColumnTypeParam* = (DpiNativeCType.INT64,
                           DpiOracleType.OTNUMBER,
                           1, false, 1)
  FloatColumnTypeParam* = (DpiNativeCType.FLOAT,
                           DpiOracleType.OTNATIVE_FLOAT,
                           1,false,0)

  DoubleColumnTypeParam* = ( DpiNativeCType.DOUBLE,
                           DpiOracleType.OTNATIVE_DOUBLE,
                           1,false,0)

  ZonedTimestampTypeParam* = (DpiNativeCType.TIMESTAMP,
                            DpiOracleType.OTTIMESTAMP_TZ,
                            1,false,0)                         

  ## predefined Int64 Type                              
  # TODO: use dpiStmt_executeMany for bulk binds
type
  SqlQuery* = distinct cstring
    ## fixme: use sqlquery from db_common
  PlSql* = distinct cstring

  PreparedStatement* = object
    relatedConn: OracleConnection
    query*: cstring
    boundParams: ParamTypeList 
    # holds all parameters - mixed in/out or inout
    stmtCacheKey*: cstring
    scrollable: bool # unused
    columnCount: uint32 # deprecated
    pStmt: ptr dpiStmt
    # ODPI-C ptr to the statement
    statementInfo*: dpiStmtInfo # populated within the execute stage
                                # TODO: eval if useable, remove otherwise
    bufferedRows*: int # refers to the maxArraySize
    # used for both reading and writing to the database 
    rsOutputCols: ParamTypeList
    # auto-populated list for returning statements
    rsCurrRow*: int # reserved for iterating
    rsMoreRows*: bool #
    rsBufferRowIndex*: int 
    # ODPI-C pointer type - unused at the moment
    rsRowsFetched*: int # stats counter
    rsColumnNames*: seq[string] 
    # populated on the first executeStatement

  ResultSet* = PreparedStatement
  # type alias

  DpiRowElement* = tuple[columnType: ColumnType,
                          columnName: string,
                          data: ptr dpiData]
    ## contains the columnType and the datapointer to the
    ## resultSets cell. the data can be fetched with the 
    ## fetch-signature templates.                         
  DpiRow* = seq[DpiRowElement]
    ## contains the DpiRowElements of the current iterated row
    ## of the ResultSet

  Lob* = object
    lobtype : ParamType
    chunkSize : uint32
    lobref : ptr dpiLob

  DpiLobType* = enum CLOB = DpiOracleType.OTCLOB,
                     NCLOB = DpiOracleType.OTNCLOB,
                     BLOB = DpiOracleType.OTBLOB
                
include odpi_obj2string
include odpi_to_nimtype
                  
template newStringColTypeParam(strlen: int): ColumnType =
  ## helper to construct a string ColumnType with specified len
  (DpiNativeCType.BYTES, DpiOracleType.OTVARCHAR, strlen, false, 0)

template newRawColTypeParam(bytelen: int): ColumnType =
  ## helper to construct a string ColumnType with specified len
  (DpiNativeCType.BYTES, DpiOracleType.OTRAW,bytelen,true, 0)

template `[]`*(row: DpiRow, colname: string): DpiRowElement =
  ## access of the iterators DpiRowElement by column name.
  ## if the column name is not present an empty row is returned
  var rowelem: DpiRowElement
  for i in row.low .. row.high:
    if cmp(colname, row[i].columnName) == 0:
      rowelem = row[i]
      break;
  rowelem

template `[]`(data: ptr dpiData, idx: int): ptr dpiData =
  ## direct access of a column's cell within the columnbuffer by index
  cast[ptr dpiData]((cast[int](data)) + (sizeof(dpiData)*idx))

template `[]`*(rs: var ResultSet, colidx: int): ParamTypeRef =
  ## selects the column of the resultSet.
  rs.rsOutputCols[colidx]

template `[]`*(rs: ParamTypeRef, rowidx: int): ptr dpiData =
  ## selects the row of the specified column
  ## the value could be extracted by the dpiData/dpiDataBuffer ODPI-C API
  ## or with the fetch-templates
  ##
  ## further reading:
  ## https://oracle.github.io/odpi/doc/structs/dpiData.html
  ## Remark: not all type combinations are implemented by ODPI-C
  cast[ptr dpiData]((cast[int](rs.buffer)) + (sizeof(dpiData)*rowidx))

proc `[]`*(rs: var PreparedStatement, bindidx: BindIdx): ParamTypeRef =
  ## retrieves the paramType for setting the parameter value by index
  ## use the setParam templates for setting the value after that.
  ## before fetching make sure that the parameter is already created
  for i in rs.boundParams.low .. rs.boundParams.high:
    if not rs.boundParams[i].isNil:
      if rs.boundParams[i].bindPosition.kind == byPosition:
        if rs.boundParams[i].bindPosition.paramVal.int == bindidx.int:
          result = rs.boundParams[i]
          return

  raise newException(IOError, "PreparedStatement[] parameterIdx : " &
    $bindidx.int & " not found!")
  {.effects.}

proc `[]`*(rs: var PreparedStatement, paramName: string): ParamTypeRef =
  ## retrieves the pointer for setting the parameter value by paramname
  ## before fetching make sure that the parameter is already created otherwise
  ## an IOError is thrown
  ## TODO: use map for paramNames
  for i in rs.boundParams.low .. rs.boundParams.high:
    if not rs.boundParams[i].isNil:
      if rs.boundParams[i].bindPosition.kind == byName:
        if cmp(paramName, rs.boundParams[i].bindPosition.paramName) == 0:
          result = rs.boundParams[i]
          return
  
  raise newException(IOError, "PreparedStatement[] parameter : " &
    paramName & " not found!")
  {.effects.}

template isDbNull*(val: ptr dpiData): bool =
  ## returns true if the value is dbNull (value not present)
  val.isNull.bool

template setDbNull*(val: ptr dpiData) =
  ## sets the value to dbNull (no value present)
  val.isNull = 1.cint

template setNotDbNull*(val: ptr dpiData) =
  ## sets value present
  val.isNull = 0.cint

include setfetchtypes
  # includes all fetch/set templates

template getColumnCount*(rs: var ResultSet): int =
  ## returns the number of columns for the ResultSet
  rs.rsColumnNames.len

proc getColumnTypeList*(rs: var ResultSet): ColumnTypeList =
  result = newSeq[ColumnType](rs.getColumnCount)
  for i in result.low .. result.high:
    result[i] = rs[i].columnType

template getNativeType*(pt: ParamTypeRef): DpiNativeCType =
  ## peeks the native type of a param. useful to determine
  ## which type the result column would be
  pt.nativeType

template getDbType*(pt: ParamTypeRef): DpiOracleType =
  ## peeks the db type of the given param
  pt.dbType

template newParamTypeList(len: int): ParamTypeList =
  # internal template ParamTypeList construction
  newSeq[ParamTypeRef](len)

template isSuccess*(result: DpiResult): bool =
  result == DpiResult.SUCCESS

template isFailure*(result: DpiResult): bool =
  result == DpiResult.FAILURE

template osql*(sql: string): SqlQuery =
  ## template to construct an oracle-SqlQuery type
  SqlQuery(sql.cstring)

proc newOracleContext*(encoding: NlsLang, authMode: DpiAuthMode,
                       outCtx: var OracleContext,
                           outMsg: var string) =
  ## constructs a new OracleContext needed to access the database.
  ## if DpiResult.SUCCESS is returned the outCtx is populated.
  ## In case of an error outMsg
  ## contains the error message.
  var ei: dpiErrorInfo
  if DpiResult(
       dpiContext_create(DPI_MAJOR_VERSION, DPI_MINOR_VERSION, addr(
       outCtx.oracleContext), ei.addr)
    ).isSuccess:
    discard dpiContext_initCommonCreateParams(outCtx.oracleContext,
        outCtx.commonParams.addr)
    discard dpiContext_initConnCreateParams(outCtx.oracleContext,
        outCtx.connectionParams.addr)
    outCtx.connectionParams.authMode = authMode.ord.uint32
    outCtx.commonParams.encoding = encoding.cstring
  else:
    raise newException(IOError, "newOracleContext: " &
      $ei )
    {.effects.}

template getErrstr*(ocontext: var OracleContext): string =
  ## checks if the last operation results with error or not
  var ei: dpiErrorInfo
  dpiContext_getError(ocontext.oracleContext, ei.addr)
  $ei
    
proc destroyOracleContext*(ocontext: var OracleContext) =
  ## destroys the present oracle context. the resultcode of this operation could
  ## be checked with hasError
  # TODO: evaluate what happens if there are open connections present
  if DpiResult(dpiContext_destroy(ocontext.oracleContext)).isFailure:
    raise newException(IOError, "newOracleContext: " &
      getErrstr(ocontext))
    {.effects.}

proc createConnection*(octx: var OracleContext,
                         connectstring: string,
                         username: string,
                         passwd: string,
                         ocOut: var OracleConnection,
                         stmtCacheSize : int = 50) =
  ## creates a connection for the given context and credentials.
  ## throws IOException in an error case
  ocOut.context = octx
  if DpiResult(dpiConn_create(octx.oracleContext, username.cstring,
    username.cstring.len.uint32,
    passwd.cstring, passwd.cstring.len.uint32, connectstring,
    connectstring.len.uint32,
    octx.commonParams.addr, octx.connectionParams.addr, addr(
        ocOut.connection))).isFailure:
    raise newException(IOError, "createConnection: " &
        getErrstr(octx))
    {.effects.}
  else:
    if DpiResult(dpiConn_setStmtCacheSize(ocOut.connection,stmtCacheSize.uint32)).isFailure:
      raise newException(IOError, "createConnection: " &
      getErrstr(octx))
    {.effects.}

proc releaseConnection*(conn: var OracleConnection) =
  ## releases the connection
  if DpiResult(dpiConn_release(conn.connection)).isFailure:
    raise newException(IOError, "createConnection: " &
      getErrstr(conn.context))
    {.effects.}
 
proc terminateExecution*(conn : var OracleConnection)  =
  ## terminates any running/pending execution on the server
  ## associated to the given connection
  if DpiResult(dpiConn_breakExecution(conn.connection)).isFailure:
    raise newException(IOError, "terminateExecution: " &
      getErrstr(conn.context))
    {.effects.}

proc setDbOperationAttribute*(conn : var OracleConnection,attribute : string) =
  ## end to end tracing for auditTrails and Enterprise Manager
  if DpiResult(dpiConn_setDbOp(conn.connection, 
               $(attribute.cstring),attribute.len.uint32)).isFailure:
    raise newException(IOError, "setDbOperationAttribute: " &
      getErrstr(conn.context))
    {.effects.}
          
proc subscribe(conn : var OracleConnection, 
               params : ptr dpiSubscrCreateParams,
               outSubscr : ptr ptr dpiSubscr)  =
  ## creates a new subscription (notification) on databas events
  # TODO: test missing              
  if DpiResult(dpiConn_subscribe(conn.connection, 
                     params,outSubscr)).isFailure:
    raise newException(IOError, "subscribe: " &
      getErrstr(conn.context))
    {.effects.}
                
proc unsubscribe(conn : var OracleConnection, subscription : ptr dpiSubscr) =
  ## unsubscribe the subscription
  # TODO: test missing
  if DpiResult(dpiConn_unsubscribe(conn.connection,subscription)).isFailure:
    raise newException(IOError, "unsubscribe: " &
      getErrstr(conn.context))
    {.effects.}
    
proc newPreparedStatement*(conn: var OracleConnection,
                           query: var SqlQuery,
                           outPs: var PreparedStatement,
                           bufferedRows: int,
                           stmtCacheKey: string = "") =
  ## constructs a new prepared statement object linked
  ## to the given specified query.
  ## the statement cache key is optional.
  ## throws IOException in an error case
  outPs.scrollable = false # always false due to not implemented
  outPs.query = cast[cstring](query)
  outPs.columnCount = 0
  outPs.relatedConn = conn

  outPs.stmtCacheKey = stmtCacheKey.cstring
  outPs.boundParams = newSeq[ParamTypeRef](0)
  outPs.bufferedRows = bufferedRows

  if DpiResult(dpiConn_prepareStmt(conn.connection, 0.cint, outPs.query,
      outPs.query.len.uint32, outPs.stmtCacheKey,
      outPs.stmtCacheKey.len.uint32, outPs.pStmt.addr)).isFailure:
    raise newException(IOError, "newPreparedStatement: " &
      getErrstr(conn.context))
    {.effects.}

  if DpiResult(dpiStmt_setFetchArraySize(
                                         outPs.pStmt,
                                         bufferedRows.uint32)
      ).isFailure:
    raise newException(IOError, "newPreparedStatement: " &
      getErrstr(conn.context))
    {.effects.}

proc newPreparedStatement*(conn: var OracleConnection,
    query: var SqlQuery,
    outPs: var PreparedStatement,
    stmtCacheKey: string = "") =
  ## convenience template to construct a preparedStatement
  ## for ddl
  newPreparedStatement(conn, query, outPs, 1, stmtCacheKey)

template bindParameter(ps: var PreparedStatement, param: ParamTypeRef) =
  # internal template to create a new in/out/inout binding variable
  var isArray: uint32 = 0
  if param.isPlSqlArray:
    isArray = 1

  if DpiResult(dpiConn_newVar(
         ps.relatedConn.connection,
         cast[dpiOracleTypeNum](param.columnType.dbType.ord),
         cast[dpiNativeTypeNum](param.columnType.nativeType.ord),
         param.rowBufferSize.uint32, #maxArraySize
    param.columnType.colsize.uint32, #size
    param.columnType.sizeIsBytes.cint,
    isArray.cint,
    nil,
    param.paramVar.addr,
    param.buffer.addr
  )).isFailure:
    raise newException(IOError, "bindParameter: " &
          "error while calling dpiConn_newVar : " & getErrstr(
              ps.relatedConn.context))
    {.effects.}

template newColumnType*(nativeType: DpiNativeCType,
                     dbType: DpiOracleType,
                     colsize: int = 1,
                     sizeIsBytes: bool = false,
                     scale: int = 1): ColumnType =
  ## construction proc for the ColumnType type.
  ## for numerical types colsize is always 1.
  ## only for varchars,blobs the colsize must
  ## be set (max). if sizeIsBytes is false,
  ## the colsize must contain the number of characters not the bytecount.
  ## TODO: templates for basic nim types
  (nativeType: nativeType, dbType: dbType,
   colsize: colsize, sizeIsBytes: sizeIsBytes,
   scale: scale)


proc addBindParameter(ps: var PreparedStatement,
                      bindInfo: BindInfo,
                      coltype: ColumnType,
                      isPlSqlArray: bool,
                      boundRows: int): ParamTypeRef =
  result = ParamTypeRef(bindPosition: bindInfo,
                         columnType: coltype,
                         paramVar: nil,
                         buffer: nil,
                         rowBufferSize: boundRows,
                         isPlSqlArray: isPlSqlArray,
                         isFetched: false)
  bindParameter(ps, result)
  ps.boundParams.add(result)


proc addBindParameter*(ps: var PreparedStatement,
                         coltype: ColumnType,
                         paramName: string) : ParamTypeRef =
  ## constructs a non-array bindparameter by parameterName.
  ## throws IOException in case of error.
  ## see https://oracle.github.io/odpi/doc/user_guide/data_types.html
  ## for supported type combinations of ColumnType.
  ## the parametername must be referenced within the
  ## query with :<paramName>
  ## after adding the parameter value can be set with the typed setters
  ## on the ParamType. the type of the parameter is implicit in,out or in/out.
  ## this depends on the underlying query
  addBindParameter(ps, BindInfo(kind: BindInfoType.byName,
                                paramName: paramName),
                    coltype,false,1.int)

proc addBindParameter*(ps: var PreparedStatement,
                         coltype: ColumnType,
                         idx: BindIdx) : ParamTypeRef =
  ## constructs a non-array bindparameter by parameter index.
  ## throws IOException in case of error.
  ## see https://oracle.github.io/odpi/doc/user_guide/data_types.html
  ## for supported type combinations of ColumnType.
  ## the parameterindex must be referenced within the
  ## query with :<paramIndex>.
  ## the parameter value can be set with the typed setters on the ParamType.
  ## the type of the parameter is implicit in,out or in/out.
  ## this depends on the underlying query
  addBindParameter(ps, BindInfo(kind: BindInfoType.byPosition,
                                paramVal: idx),
                  coltype,false,1.int)
           
proc addArrayBindParameter*(ps: var PreparedStatement,
                       coltype: ColumnType,
                       paramName: string,
                       rowCount : int, 
                       isPlSqlArray : bool = false) : ParamTypeRef =
  ## constructs an array bindparameter by parameterName.
  ## array parameters are used for bulk-insert or plsql-array-handling
  ## throws IOException in case of error.
  ## see https://oracle.github.io/odpi/doc/user_guide/data_types.html
  ## for supported type combinations of ColumnType.
  ## the parametername must be referenced within the
  ## query with :<paramName>
  ## after adding the parameter value can be set with the typed setters
  ## on the ParamType. the type of the parameter is implicit in,out or in/out.
  ## this depends on the underlying query
  if ps.bufferedRows < rowCount:
    raise newException(IOError, "addArrayBindParameter: " &
      "given rowCount of " & $rowCount & " exceeds the preparedStatements maxBufferedRows" )
    {.effects.}
  
  addBindParameter(ps, BindInfo(kind: BindInfoType.byName,
                  paramName: paramName),
                  coltype,isPlSqlArray,rowCount)

proc addArrayBindParameter*(ps: var PreparedStatement,
           coltype: ColumnType,
           idx: BindIdx,
           rowCount : int, 
           isPlSqlArray : bool = false): ParamTypeRef =
  ## constructs a array bindparameter by parameter index.
  ## array parameters are used for bulk-insert or plsql-array-handling.
  ## throws IOException in case of error.
  ## see https://oracle.github.io/odpi/doc/user_guide/data_types.html
  ## for supported type combinations of ColumnType.
  ## the parameterindex must be referenced within the
  ## query with :<paramIndex>.
  ## the parameter value can be set with the typed setters on the ParamType.
  ## the type of the parameter is implicit in,out or in/out.
  ## this depends on the underlying query
  if ps.bufferedRows < rowCount:
    raise newException(IOError, "addArrayBindParameter: " &
      "given rowCount of " & $rowCount & " exceeds the preparedStatements maxBufferedRows" )
    {.effects.}

  addBindParameter(ps, BindInfo(kind: BindInfoType.byPosition,
                   paramVal: idx),
                   coltype,isPlSqlArray,rowcount)


proc addOutColumn(rs: var ResultSet, columnParam: ParamTypeRef) =
  ## binds out-parameters to the specified resultset according to the
  ## metadata given by the database. used to construct the resultSet.
  ## throws IOException in case of error
  let index: int = columnParam.bindPosition.paramVal.int-1
  rs.rsOutputCols[index] = columnParam
  bindParameter(rs, columnParam)
  if DpiResult(dpiStmt_define(rs.pStmt,
                                  (index+1).uint32,
                                  columnParam.paramVar)).isFailure:
    raise newException(IOError, "addOutColumn: " & $columnParam &
      getErrstr(rs.relatedConn.context))
    {.effects.}


proc destroy*(prepStmt: var PreparedStatement) =
  ## frees the preparedStatements internal resources.
  ## this should be called if
  ## the prepared statement is no longer in use.
  ## additional resources of a present resultSet
  ## are also freed. a preparedStatement with refCursor can not
  ## be reused.
  for i in prepStmt.boundParams.low .. prepStmt.boundParams.high:
    discard dpiVar_release(prepStmt.boundParams[i].paramVar)
  for i in prepStmt.rsOutputCols.low .. prepStmt.rsOutputCols.high:
    discard dpiVar_release(prepStmt.rsOutputCols[i].paramVar)
  prepStmt.boundParams.setLen(0)
  prepStmt.rsOutputCols.setLen(0)
  discard dpiStmt_release(prepStmt.pStmt)

                              
proc executeAndInitResultSet(prepStmt: var PreparedStatement,
                         dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord,
                         isRefCursor: bool = false) =
  # internal proc. initialises the derived ResultSet
  # from the given preparedStatement by calling execute on it
  # TODO: reset() needed
  prepStmt.rsMoreRows = true
  prepStmt.rsRowsFetched = 0

  if not isRefCursor:
  # TODO: get rid of quirky isRefCursor flag
    if prepStmt.boundParams.len > 0 and
         prepStmt.boundParams[0].rowBufferSize > 1:
      ## bulk insert - no results are fetched
      if DpiResult(dpiStmt_executeMany(prepStmt.pStmt,
                                       dpimode,
                                       prepStmt.bufferedRows.
                                         uint32)).isFailure:
        raise newException(IOError, "executeMany: " &
          getErrstr(prepStmt.relatedConn.context))
        {.effects.}
    else:
      if DpiResult(
           dpiStmt_execute(prepStmt.pStmt,
                           dpiMode,
                           prepStmt.columnCount.addr)
                  ).isFailure:
        raise newException(IOError, "executeAndInitResultSet: " &
                getErrstr(prepStmt.relatedConn.context))
        {.effects.}              
  else:
    discard dpiStmt_getNumQueryColumns(prepStmt.pStmt,
        prepStmt.columnCount.addr)
    if DpiResult(
           dpiStmt_setFetchArraySize(prepStmt.pStmt,
                                     prepStmt.bufferedRows.uint32)
      ).isFailure:
      raise newException(IOError, "executeAndInitResultSet(refcursor): " &
        getErrstr(prepStmt.relatedConn.context))
      {.effects.}

  if prepStmt.rsOutputCols.len <= 0:
    # create the needed buffercolumns(resultset) automatically
    # only once
    prepStmt.rsOutputCols = newParamTypeList(prepStmt.columnCount.int)
    prepStmt.rsColumnNames = newSeq[string](prepStmt.columnCount.int)
    discard dpiStmt_getInfo(prepStmt.pStmt, prepStmt.statementInfo.addr)

    var qInfo: dpiQueryInfo
    for i in countup(1, prepStmt.columnCount.int):
      # extract needed params out of the metadata
      # the columnindex starts with 1
      # TODO: if a type is not supported by ODPI-C
      # log error within the ParamType
      discard dpiStmt_getQueryInfo(prepStmt.pStmt, i.uint32, qInfo.addr)
      var colname = newString(qInfo.nameLength)
      copyMem(addr(colname[0]), qInfo.name.ptr, colname.len)

      prepStmt.rsColumnNames[i-1] = colname
      prepStmt.rsOutputCols[i-1] = ParamTypeRef(
                          bindPosition: BindInfo(kind: BindInfoType.byPosition,
                                               paramVal: BindIdx(i)),
                          queryInfo: qInfo,
                          columnType: (nativeType: DpiNativeCType(
                                       qinfo.typeinfo.defaultNativeTypeNum),
                                       dbType: DpiOracleType(
                                       qinfo.typeinfo.oracleTypeNum),
                          colSize: qinfo.typeinfo.clientSizeInBytes.int,
                          sizeIsBytes: true, scale: qinfo.typeinfo.scale.int),
                          paramVar: nil,
                          buffer: nil,
                          rowBufferSize: prepStmt.bufferedRows)
                          # each out-resultset param owns the rowbuffersize
                          # of the prepared statement
      addOutColumn(prepStmt, prepStmt.rsOutputCols[i-1])

template openRefCursor(ps : PreparedStatement, 
                       p : ParamTypeRef,
                       outRefCursor : var ResultSet,
                       bufferedRows : int,
                       dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord) =
  if param.isFetched:
    # quirky
    raise newException(IOError, "openRefCursor: " &
       """ reexecute of the preparedStatement with refCursor not supported """)
    {.effects.}
                    
  if param.columnType.nativeType == DpiNativeCType.STMT and
    param.columnType.dbType == DpiOracleType.OTSTMT:
    param.isFetched = true
    outRefCursor.pstmt = param[0].fetchRefCursor
    outRefCursor.relatedConn = ps.relatedConn
    outRefCursor.bufferedRows = bufferedRows
  
    executeAndInitResultSet(outRefCursor,dpiMode,true)
  
  else:
    raise newException(IOError, "openRefCursor: " &
      """ bound parameter has not the required
          DpiNativeCType.STMT/DpiOracleType.OTSTMT 
          combination """)
    {.effects.}
                    

proc openRefCursor*(ps: var PreparedStatement, idx : BindIdx,
                    outRefCursor: var ResultSet,
                    bufferedRows: int,
                    dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord) =
  ## opens the refcursor on the specified bind parameter.
  ## executeStatement must be called before open it.
  ## throws IOError in case of an error
  let param : ParamTypeRef = ps[idx.BindIdx]
  openRefCursor(ps,param,outRefCursor,bufferedRows,dpiMode)

proc openRefCursor*(ps: var PreparedStatement, 
                      paramName : string,
                      outRefCursor: var ResultSet,
                      bufferedRows: int,
                      dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord) =
  ## opens the refcursor on the specified bind parameter.
  ## executeStatement must be called before open it.
  ## throws IOError in case of an error
  let param = ps[paramName]
  openRefCursor(ps,param,outRefCursor,bufferedRows,dpiMode)


# proc closeRefCursor*(rs: var ResultSet) =
# deprecated. binds are release on destroy or by the preparedStatement
# with-template
#  ## releases refCursors output-binds
#  for i in rs.rsOutputCols.low .. rs.rsOutputCols.high:
#    discard dpiVar_release(rs.rsOutputCols[i].paramVar)
#  rs.rsOutputCols.setLen(0)

proc executeStatement*(prepStmt: var PreparedStatement,
  numRows: int,
  dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord) =
  ## executes the statement without returning any rows.
  ## suitable for bulk insert
  discard
  # TODO: implement

proc updateBindParams(prepStmt: var PreparedStatement, rowBufferSize : int) =
  # reread the params for reexecution of the prepared statement 
  for i in prepStmt.boundParams.low .. prepStmt.boundParams.high:
    let bp = prepStmt.boundParams[i]
    if rowBufferSize > 1:
      discard dpiVar_setNumElementsInArray(bp.paramVar,
                                           rowBufferSize.uint32)

    if bp.bindPosition.kind == BindInfoType.byPosition:
      if DpiResult(dpiStmt_bindByPos(prepStmt.pStmt,
                                     bp.bindPosition.paramVal.uint32,
                                     bp.paramVar
        )
      ).isFailure:
        raise newException(IOError, "bindArrayParams: " &
                  getErrstr(prepStmt.relatedConn.context))
        {.effects.}

    elif bp.bindPosition.kind == BindInfoType.byName:
      if DpiResult(dpiStmt_bindByName(prepStmt.pStmt,
                                     bp.bindPosition.paramName,
                                     bp.bindPosition.paramName.len.uint32,
                                     bp.paramVar
        )
      ).isFailure:
        raise newException(IOError, "bindArrayParams: " &
                         $bp.bindPosition.paramName &
                           getErrstr(prepStmt.relatedConn.context))
        {.effects.}  

proc executeStatement*(prepStmt: var PreparedStatement,
                        outRs: var ResultSet,
                        dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord) =
  ## the results can be fetched
  ## on a col by col base. once executed the bound columns can be reused
  ##
  ## multiple dpiMode's can be "or"ed together.
  ## raises IOError in case of an error

  # probe if binds present
  if prepStmt.boundParams.len > 0:
    updateBindParams(prepStmt,prepStmt.bufferedRows)
    # FIXME: track the number of rows within the statement, not the param

  prepStmt.executeAndInitResultSet(dpiMode, false)
  outRs = cast[ResultSet](prepStmt)

proc fetchNextRows*(rs: var ResultSet) =
  ## fetches next rows (if present) into the internal buffer.
  ## if DpiResult.FAILURE is returned the internal error could be retrieved
  ## by calling getErrstr on the context.
  ##
  ## After fetching, the window can be accessed by using the
  ## "[<colidx>][<rowidx>]" operator on the resultSet.
  ## No bounds check is performed.
  ## the colidx should not exceed the maximum column-count and the
  ## rowidx should not exceed the given fetchArraySize
  ##
  ## remark: no data-copy is performed.
  ## blobs and strings (pointer types) should be copied into the application
  ## domain before calling fetchNextRows again.
  ## value types are copied on assignment
  if rs.rsMoreRows:
    var moreRows: cint # out
    var bufferRowIndex: uint32 # out
    var rowsFetched: uint32 #out

    if DpiResult(dpiStmt_fetchRows(rs.pStmt,
                                   rs.bufferedRows.uint32,
                                   bufferRowIndex.addr,
                                   rowsFetched.addr,
                                   moreRows.addr)).isSuccess:
      rs.rsMoreRows = moreRows.bool
      rs.rsBufferRowIndex = bufferRowIndex.int
      rs.rsRowsFetched = rowsFetched.int
    else:
      raise newException(IOError, "fetchNextRows: " &
        getErrstr(rs.relatedConn.context))
      {.effects.}
  

iterator columnTypesIterator*(rs : var ResultSet) : tuple[idx : int, ct: ColumnType] = 
  ## iterates over the resultSets columnTypes if present
  var ctl: ColumnTypeList = rs.getColumnTypeList
  for i in countup(ctl.low,ctl.high):
    yield (i,ctl[i])

iterator resultSetRowIterator*(rs: var ResultSet): DpiRow =
  ## iterates over the resultset row by row. no data copy is performed
  ## and the ptr type values should be copied into the application
  ## domain before the next window is requested.
  ## do not use this iterator in conjunction with fetchNextRows because
  ## it's already used internally.
  ## in an error case an IOException is thrown with the error message retrieved
  ## out of the context.
  var p: DpiRow = newSeq[DpiRowElement](rs.rsOutputCols.len)
  var paramtypes = rs.getColumnTypeList
  rs.rsCurrRow = 0
  rs.rsRowsFetched = 0

  fetchNextRows(rs)
  
  while rs.rsCurrRow < rs.rsRowsFetched:
    for i in rs.rsOutputCols.low .. rs.rsOutputCols.high:
      p[i] = (columnType: paramtypes[i],
              columnname: rs.rsColumnNames[i],
              data: rs.rsOutputCols[i][rs.rsCurrRow])
      # construct column
    yield p
    inc rs.rsCurrRow
    if rs.rsCurrRow == rs.rsRowsFetched and rs.rsMoreRows:
      fetchNextRows(rs)
      rs.rsCurrRow = 0

iterator bulkBindIterator*(pstmt: var PreparedStatement,
                           rs: var ResultSet,
                           maxRows : int,
                           maxRowBufferIdx : int): 
                              tuple[rowcounter:int,
                                    buffercounter:int] =
  ## convenience iterator for bulk binding.
  ## it will countup to maxRows but will return the next
  ## index of the rowBuffer. maxRowBufferIdx is the high watermark.
  ## if it is reached executeStatement is called automatically
  ## and the internal counter is reset to 0.
  if maxRows < maxRowBufferIdx:
    raise newException(IOError,"bulkBindIterator: " &
      "constraint maxRows < maxRowBufferIdx violated " )
    {.effects.}  

  var rowBufferIdx = 0.int
  
  for i in countup(0,maxRows):
    yield (rowcounter:i,buffercounter:rowBufferIdx)
    if rowBufferIdx == maxRowBufferIdx:
      # if high watermark reached flush the buffer
      # to db and reset the buffer counter
      pstmt.executeStatement(rs)
      rowBufferIdx = 0
    else:
      inc rowBufferIdx                     
  
  if rowBufferIdx > 0:
    # rows iterator finished but unsent data within buffer
    updateBindParams(pstmt,rowBufferIdx)
    if DpiResult(dpiStmt_executeMany(pstmt.pStmt,
                                    DpiModeExec.DEFAULTMODE.ord,
                                    pstmt.bufferedRows.uint32)).isFailure:
      raise newException(IOError, "executeMany: " &
        getErrstr(pstmt.relatedConn.context))
      {.effects.} 

template withTransaction*(dbconn: OracleConnection,
    body: untyped) =
  ## used to encapsulate the operation within a transaction.
  ## if an exception is thrown (within the body) the
  ## transaction will be rolled back.
  ## note that a dml operation creates a implicit transaction.
  ## the DpiResult is used as a feedback channel on
  ## the commit/rollback-operation. at the
  ## moment it contains only the returncode from the commit/rolback ODPI-C call
  block:
    try:
      body
      if DpiResult(dpiConn_commit(dbconn.connection)).isFailure:
        raise newException(IOError, "withTransaction: " &
          getErrstr(rs.relatedConn.context) )
        {.effects.}
    except:
      discard dpiConn_rollback(dbconn.connection)
      raise


template withPreparedStatement*(ps: var PreparedStatement, body: untyped) =
  ## releases the preparedStatement after leaving
  ## the block.
  try:
    body
  finally:
    ps.destroy

proc executeDDL*(conn: var OracleConnection,
                 sql: var SqlQuery,
                 dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord) =
  ## convenience template to execute a ddl statement (no results returned)
  var rs: ResultSet
  var p: PreparedStatement
  newPreparedStatement(conn, sql, p)

  withPreparedStatement(p):
    discard dpiStmt_getInfo(p.pStmt, p.statementInfo.addr)
    if p.statementInfo.isDDL == 1:
      p.executeStatement(rs, dpiMode)
    else:
      raise newException(IOError, "executeDDL: " &
        " statement is no DDL. please use executeStatement instead.")
      {.effects.}


proc newTempLob*( conn : var OracleConnection, 
                  lobtype : DpiLobType, 
                  outlob : var Lob )  = 
  ## creates a new temp lob
  if DpiResult(dpiConn_newTempLob(conn.connection,
               lobtype.ord.dpiOracleTypeNum,
               addr(outlob.lobref))).isFailure:
    raise newException(IOError, "createConnection: " &
      getErrstr(conn.context))
    {.effects.}

when isMainModule:
  ## the HR Schema is used (XE) for the following tests
  const
    lang: NlsLang = "UTF8".NlsLang
    oracleuser: string = "sys"
    pw: string = "<pwd>"
    connectionstr: string = """(DESCRIPTION = (ADDRESS = 
                             (PROTOCOL = TCP)
                             (HOST = localhost)  
                             (PORT = 1521))
                             (CONNECT_DATA =(SERVER = DEDICATED)
                             (SERVICE_NAME = XEPDB1 )
                            ))"""

  var octx: OracleContext
  var errmsg: string

  newOracleContext(lang, DpiAuthMode.SYSDBA, octx, errmsg)
  # create the context with the nls_lang and authentication Method
  var conn: OracleConnection

  createConnection(octx, connectionstr, oracleuser, pw, conn)
  # create the connection with the desired server, 
  # credentials and the context

  var query: SqlQuery = osql"""select 100 as col1, 'äöü' as col2 from dual 
  union all  
  select 200 , 'äöü2' from dual
  union all
  select 300 , 'äöü3' from dual
  """
  # query is unused at the moment

  var query2: SqlQuery = osql""" select 
          rowid,
          EMPLOYEE_ID, 
          FIRST_NAME, 
          LAST_NAME, 
          EMAIL, 
          PHONE_NUMBER, 
          HIRE_DATE, 
          JOB_ID, 
          SALARY, 
          COMMISSION_PCT, 
          MANAGER_ID, 
          DEPARTMENT_ID 
    from hr.employees where department_id = :param1  """


  var pstmt: PreparedStatement

  newPreparedStatement(conn, query2, pstmt, 10)
  # create prepared statement for the specified query and
  # the number of buffered result-rows. the number of buffered
  # rows (window) is fixed and can't changed later on
  var rs: ResultSet

  var param = addBindParameter(pstmt,
             Int64ColumnTypeParam,
              "param1")
  param.setInt64(some(80.int64))
  # create and set the bind parameter. query bind
  # parameter are always non-columnar. 

  executeStatement(pstmt,rs)
  # execute the statement. if the resulting rows
  # fit into entire window we are done here.
  var ctl: ColumnTypeList = rs.getColumnTypeList

  for i,ct in rs.columnTypesIterator:
    echo "cname:" & rs.rsColumnNames[i] & " colnumidx: " & 
      $(i+1) & " " & $ct

  for row in resultSetRowIterator(rs):
    # the result iterator fetches internally further
    # rows if present 
    # example of value retrieval by columnname or index
    echo $fetchRowId(row[0].data) &
    " " & $fetchDouble(row[1].data) &
    " " & $fetchString(row["FIRST_NAME"].data) &
    " " & $fetchString(row["LAST_NAME"].data) &
    " " & $fetchInt64(row[10].data) &
    " " & $fetchInt64(row[11].data)

  echo "query1 executed - param department_id = 80 "
  # reexecute preparedStatement with a different parameter value
  param.setInt64(some(10.int64))
  executeStatement(pstmt, rs)
  # the parameter is changed here and the query is 
  # re-executed 

  for row in resultSetRowIterator(rs):
    # retrieve column values by columnname or index
    echo $fetchRowId(row[0].data) &
      " " & $fetchDouble(row[1].data) &
      " " & $fetchString(row["FIRST_NAME"].data) &
      " " & $fetchString(row["LAST_NAME"].data) &
      " " & $fetchInt64(row[10].data) &
      " " & $fetchInt64(row[11].data)
  
  echo "query1 executed 2nd run - param department_id = 10 "

  pstmt.destroy
  # the prepared statement is destroyed and the 
  # resources are freed (mandatory). the withPreparedStatement
  # template calls this implicit.  

  # TODO: plsql example with types and select * from table( .. )

  var refCursorQuery: SqlQuery = osql""" begin 
      open :1 for select 'teststr' StrVal from dual 
                          union all 
                  select 'teststr1' from dual; 
      open :refc2 for select first_name,last_name 
                   from hr.employees 
                    where department_id = :3;
      end; """
  # FIXME: typed plsql blocks

  var pstmt2 : PreparedStatement
  # refcursor example
  newPreparedStatement(conn, refCursorQuery, pstmt2, 1)
  # this query block contains two independent refcursors
  # and the snd is parameterised.

  withPreparedStatement(pstmt2):
    discard pstmt2.addBindParameter(RefCursorColumnTypeParam,BindIdx(1))
    # to consume the refcursor a bindParameter is needed                                   
    discard pstmt2.addBindParameter(RefCursorColumnTypeParam,"refc2")
    # example of bind by name
    discard pstmt2.addBindParameter(Int64ColumnTypeParam,BindIdx(3))
    # filter: parameter for department_id                                   
    pstmt2[3.BindIdx].setInt64(some(80.int64))

    pstmt2.executeStatement(rs)

    echo "refCursor 1 results: "
    var refc: ResultSet

    pstmt2.openRefCursor(1.BindIdx, refc, 1, DpiModeExec.DEFAULTMODE.ord)
    # opens the refcursor. once consumed it can't be reopended (TODO: check
    # if that's a ODPI-C limitation)
    for row in resultSetRowIterator(refc):
      echo $fetchString(row[0].data)

    echo "refCursor 2 results: filter with department_id = 80 "

    var refc2 : ResultSet
    pstmt2.openRefCursor("refc2", refc2, 10, DpiModeExec.DEFAULTMODE.ord)

    for row in resultSetRowIterator(refc2):
      echo $fetchString(row[0].data) & " " & $fetchString(row[1].data)

  var ctableq = osql""" CREATE TABLE HR.DEMOTESTTABLE(
                        C1 VARCHAR2(20) NOT NULL 
                      , C2 NUMBER(5,0)
                      , C3 raw(20) 
                      , C4 NUMBER(5,3)
                      , C5 NUMBER(15,5)
                      , C6 TIMESTAMP 
    ) """
  # , CONSTRAINT DEMOTESTTABLE_PK PRIMARY KEY(C1)

  conn.executeDDL(ctableq) 

  var insertStmt: SqlQuery =
    osql""" insert into HR.DEMOTESTTABLE(C1,C2,C3,C4,C5,C6) 
                                values (:1,:2,:3,:4,:5,:6) """

  var pstmt3 : PreparedStatement
  conn.newPreparedStatement(insertStmt, pstmt3, 10)

  # bulk insert example. 55 rows are inserted with a buffer
  # window of 10 rows

  discard pstmt3.addArrayBindParameter(newStringColTypeParam(20),
             BindIdx(1), 10)
  discard pstmt3.addArrayBindParameter(Int64ColumnTypeParam,
                                  BindIdx(2), 10)
  discard pstmt3.addArrayBindParameter(newRawColTypeParam(5),
             3.BindIdx,10)
  discard pstmt3.addArrayBindParameter(FloatColumnTypeParam,
             4.BindIdx,10)                  
  discard pstmt3.addArrayBindParameter(DoubleColumnTypeParam,
              5.BindIdx,10)                  
  discard pstmt3.addArrayBindParameter(ZonedTimestampTypeParam,
               6.BindIdx,10)

  # if a nativeType/oracleType combination is not implemented by ODPI-C
  # you will receive an exception here

  var rset: ResultSet

  conn.withTransaction: # commit after this block
    withPreparedStatement(pstmt3): # cleanup of preparedStatement
      var varc2 : Option[int64]
      for i,widx in pstmt3.bulkBindIterator(rset,55,9):
        # i: count over entire 55 entries, widx: window index
        # convenience iterator. if the window is filled
        # contents are flushed to the database.
        if i == 9:
          varc2 = none(int64) # simulate dbNull
        else:
          varc2 = some(i.int64)
        # unfortunately setString/setBytes have a different
        # API than the value-parameter types
        pstmt3[1.BindIdx].setString(widx,some("test_äüö" & $i)) #pk
        pstmt3[2.BindIdx][widx].setInt64(varc2)
        # the fastest access is by ParamTypeRef directly (no param lookup)
        pstmt3[3.BindIdx].setBytes(widx,some(@[(0xAA+i).byte,0xBB,0xCC]))
        pstmt3[4.BindIdx][widx].setFloat(some(i.float32+0.12.float32))
        pstmt3[5.BindIdx][widx].setDouble(some(i.float64+99.12345))
        pstmt3[6.BindIdx][widx].setDateTime(some(getTime().local))

  var selectStmt: SqlQuery = osql"""select c1,c2,rawtohex(c3)
                                         as c3,c4,c5,c6 from hr.demotesttable"""
      # read now the committed stuff

  var pstmt4 : PreparedStatement
  var rset4 : ResultSet

  conn.newPreparedStatement(selectStmt, pstmt4, 4)
      # 4 rows are buffered internally

  withPreparedStatement(pstmt4): 
    pstmt4.executeStatement(rset4)
    for row in resultSetRowIterator(rset4):       
      echo $fetchString(row[0].data) & "  " & $fetchInt64(row[1].data) & 
            " " & $fetchString(row[2].data) & 
          # " "  & $fetchFloat(row[3].data) &
          # TODO: eval float32 vals 
            " " & $fetchDouble(row[4].data) & " " & $(fetchDateTime(row[5].data).get)
          # FIXME: fetchFloat returns wrong values / dont work as expected

      # drop the table
  var dropStmt: SqlQuery = osql"drop table hr.demotesttable"
  conn.executeDDL(dropStmt)
      # cleanup - table drop


  conn.releaseConnection
  destroyOracleContext(octx)
