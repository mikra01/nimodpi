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
                      scale: int8,
                      name : string,
                      precision : int16,
                      fsPrecision : int16 ] # scale used for some numeric types
  ColumnTypeList* = seq[ColumnType]
  # predefined column types

const
  NlsLangDefault = "UTF8".NlsLang
  RefCursorColumnTypeParam* = (DpiNativeCType.STMT,
                               DpiOracleType.OTSTMT,
                               1, false, 1.int8,"",0.int16,0.int16).ColumnType
  ## predefined parameter for refcursor                                 
  Int64ColumnTypeParam* = (DpiNativeCType.INT64,
                           DpiOracleType.OTNUMBER,
                           1, false, 1.int8,"",0.int16,0.int16).ColumnType
  FloatColumnTypeParam* = (DpiNativeCType.FLOAT,
                           DpiOracleType.OTNATIVE_FLOAT,
                           1,false,0.int8,"",0.int16,0.int16).ColumnType
  DoubleColumnTypeParam* = ( DpiNativeCType.DOUBLE,
                           DpiOracleType.OTNATIVE_DOUBLE,
                           1,false,0.int8,"",0.int16,0.int16).ColumnType
  ZonedTimestampTypeParam* = (DpiNativeCType.TIMESTAMP,
                            DpiOracleType.OTTIMESTAMP_TZ,
                            1,false,0.int8,"",0.int16,0.int16).ColumnType
  # FIXME: populate scale, precision for fp-types                                                   

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
    # used to allocate new vars for plsql
    # type params
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

  DpiRow* = object
    rset : ResultSet 
    rawRow : seq[ptr dpiData]
    ## contains all data pointers of the current iterated row
    ## of the ResultSet

  OracleObjType* = object
    ## wrapper for the object type database handles
    relatedConn : OracleConnection
    baseHdl : ptr dpiObjectType
    objectTypeInfo : dpiObjectTypeInfo
    isCollection : bool
    attributes : seq[ptr dpiObjectAttr]
    columnTypeList : ColumnTypeList
    # columnTypeList and attributes are in the
    # same order

  OracleObj* = object
    ## wrapper for an object instance
    objType : OracleObjType
    objHdl : ptr dpiObject
    paramVar : ptr dpiVar
    bufferedColumn : seq[ptr dpiData]
    
  Lob* = object
    lobtype : ParamType
    chunkSize : uint32
    lobref : ptr dpiLob

  DpiLobType* = enum CLOB = DpiOracleType.OTCLOB,
                     NCLOB = DpiOracleType.OTNCLOB,
                     BLOB = DpiOracleType.OTBLOB
                
include odpi_obj2string
include odpi_to_nimtype
include nimtype_to_odpi                  

template newStringColTypeParam*(strlen: int): ColumnType =
  ## helper to construct a string ColumnType with specified len
  (DpiNativeCType.BYTES, DpiOracleType.OTVARCHAR, strlen, false, 0.int8,
   "",0.int16,0.int16
  )

template newRawColTypeParam*(bytelen: int): ColumnType =
  ## helper to construct a string ColumnType with specified len
  (DpiNativeCType.BYTES, DpiOracleType.OTRAW,bytelen,true, 0.int8,
   "",0.int16,0.int16
  )

template `[]`*(rs: var ResultSet, colidx: int): ParamTypeRef =
  ## selects the column of the resultSet.
  rs.rsOutputCols[colidx]

template `[]`*(row: DpiRow, colname: string): ptr dpiData =
  ## access of the iterators dataCell by column name.
  ## if the column name is not present an nil ptr is returned
  var cellptr : ptr dpiData = cast[ptr dpiData](0)
  for i in row.rawRow.low .. row.rawRow.high:
    if cmp(colname, row.rset.rsOutputCols[i].columnType.name) == 0:
      cellptr = row.rawRow[i]
      break;
  cellptr

template `[]`*(row: DpiRow, index : int ): ptr dpiData =
  ## access of the iterators dataCell by index (starts with 0)
  var cellptr = row.rawRow[index]
  cellptr  

template `[]`(data: ptr dpiData, idx: int): ptr dpiData =
  ## direct access of a column's cell within the columnbuffer by index.
  ## internal - used by DpiRow for calculating the ptr
  cast[ptr dpiData]((cast[int](data)) + (sizeof(dpiData)*idx))


template `[]`*(rs: ParamTypeRef, rowidx: int): ptr dpiData =
  ## selects the row of the specified column
  ## the value could be extracted by the dpiData/dpiDataBuffer ODPI-C API
  ## or with the fetch-templates
  ##
  ## further reading:
  ## https://oracle.github.io/odpi/doc/structs/dpiData.html
  ## Remark: not all type combinations are implemented by ODPI-C
  rs.buffer[rowidx]
  
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

template getColumnType*(rs : var ResultSet, idx : BindIdx) : ColumnType =
  ## fetches the columntype of the resulting column set by index
  rs[idx.int].columnType

template getBoundColumnType*( ps : var PreparedStatement, idx : BindIdx) : ColumnType =
  ## fetches the columntype of a bound parameter by index
  ps.boundParams[idx.int].columnType

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

proc newOracleContext*(outCtx: var OracleContext, 
                       authMode : DpiAuthMode,
                       encoding : NlsLang = NlsLangDefault ) =
  ## constructs a new OracleContext needed to access the database.
  ## if DpiResult.SUCCESS is returned the outCtx is populated.
  ## In case of an error an IOException is thrown.
  ## the commonParams createMode is always DPI_MODE_CREATE_THREADED
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
    outCtx.commonParams.createMode = DPI_MODE_CREATE_THREADED
  else:
    raise newException(IOError, "newOracleContext: " &
      $ei )
    {.effects.} 

template getErrstr(ocontext: ptr dpiContext): string =
  ## checks if the last operation results with error or not
  var ei: dpiErrorInfo
  dpiContext_getError(ocontext, ei.addr)
  $ei
    
proc destroyOracleContext*(ocontext: var OracleContext) =
  ## destroys the present oracle context. the resultcode of this operation could
  ## be checked with hasError
  # TODO: evaluate what happens if there are open connections present
  if DpiResult(dpiContext_destroy(ocontext.oracleContext)).isFailure:
    raise newException(IOError, "newOracleContext: " &
      getErrstr(ocontext.oracleContext))
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
        getErrstr(octx.oracleContext))
    {.effects.}
  else:
    if DpiResult(dpiConn_setStmtCacheSize(ocOut.connection,
                                          stmtCacheSize.uint32)).isFailure:
      raise newException(IOError, "createConnection: " &
      getErrstr(octx.oracleContext))
    {.effects.}

proc releaseConnection*(conn: var OracleConnection) =
  ## releases the connection
  if DpiResult(dpiConn_release(conn.connection)).isFailure:
    raise newException(IOError, "createConnection: " &
      getErrstr(conn.context.oracleContext))
    {.effects.}
 
proc terminateExecution*(conn : var OracleConnection)  =
  ## terminates any running/pending execution on the server
  ## associated to the given connection
  if DpiResult(dpiConn_breakExecution(conn.connection)).isFailure:
    raise newException(IOError, "terminateExecution: " &
      getErrstr(conn.context.oracleContext))
    {.effects.}

proc setDbOperationAttribute*(conn : var OracleConnection,attribute : string) =
  ## end to end tracing for auditTrails and Enterprise Manager
  if DpiResult(dpiConn_setDbOp(conn.connection, 
               $(attribute.cstring),attribute.len.uint32)).isFailure:
    raise newException(IOError, "setDbOperationAttribute: " &
      getErrstr(conn.context.oracleContext))
    {.effects.}
          
proc subscribe(conn : var OracleConnection, 
               params : ptr dpiSubscrCreateParams,
               outSubscr : ptr ptr dpiSubscr)  =
  ## creates a new subscription (notification) on databas events
  # TODO: test missing              
  if DpiResult(dpiConn_subscribe(conn.connection, 
                     params,outSubscr)).isFailure:
    raise newException(IOError, "subscribe: " &
      getErrstr(conn.context.oracleContext))
    {.effects.}
                
proc unsubscribe(conn : var OracleConnection, subscription : ptr dpiSubscr) =
  ## unsubscribe the subscription
  # TODO: test missing
  if DpiResult(dpiConn_unsubscribe(conn.connection,subscription)).isFailure:
    raise newException(IOError, "unsubscribe: " &
      getErrstr(conn.context.oracleContext))
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
      getErrstr(conn.context.oracleContext))
    {.effects.}

  if DpiResult(dpiStmt_setFetchArraySize(
                                         outPs.pStmt,
                                         bufferedRows.uint32)
      ).isFailure:
    raise newException(IOError, "newPreparedStatement: " &
      getErrstr(conn.context.oracleContext))
    {.effects.}

template newPreparedStatement*(conn: var OracleConnection,
    query: var SqlQuery,
    outPs: var PreparedStatement,
    stmtCacheKey: string = "") =
  ## convenience template to construct a preparedStatement
  ## for ddl
  newPreparedStatement(conn, query, outPs, 1, stmtCacheKey)


template releaseParameter(ps : var PreparedStatement, param : ParamTypeRef) =
  ## frees the internal dpiVar resources
  if DpiResult(dpiVar_release(param.paramVar)).isFailure:
    raise newException(IOError, " releaseParameter: " &
    "error while calling dpiVar_release : " & getErrstr(
        ps.relatedConn.context.oracleContext))
    {.effects.}

template newVar(ps: var PreparedStatement, param: ParamTypeRef) =
  # internal template to create a new in/out/inout binding variable
  # according to the ParamTypeRef's settings
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
              ps.relatedConn.context.oracleContext))
    {.effects.}


proc newParamTypeRef(ps: var PreparedStatement,
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
  result = newParamTypeRef(ps, BindInfo(kind: BindInfoType.byName,
                                paramName: paramName),
                    coltype,false,1.int)
  newVar(ps, result)
  ps.boundParams.add(result)

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
  result = newParamTypeRef(ps, BindInfo(kind: BindInfoType.byPosition,
                                paramVal: idx),
                  coltype,false,1.int)
  newVar(ps, result)
  ps.boundParams.add(result)
                           
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
      "given rowCount of " & $rowCount & 
      " exceeds the preparedStatements maxBufferedRows" )
    {.effects.}
  
  result = newParamTypeRef(ps, BindInfo(kind: BindInfoType.byName,
                  paramName: paramName),
                  coltype,isPlSqlArray,rowCount)
  newVar(ps, result)
  ps.boundParams.add(result)
                
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
      "given rowCount of " & $rowCount & 
      " exceeds the preparedStatements maxBufferedRows" )
    {.effects.}

  result = newParamTypeRef(ps, BindInfo(kind: BindInfoType.byPosition,
                   paramVal: idx),
                   coltype,isPlSqlArray,rowcount)
  newVar(ps, result)
  ps.boundParams.add(result)
                 
proc destroy*(prepStmt: var PreparedStatement) =
  ## frees the preparedStatements internal resources.
  ## this should be called if
  ## the prepared statement is no longer in use.
  ## additional resources of a present resultSet
  ## are also freed. a preparedStatement with refCursor can not
  ## be reused.
  for i in prepStmt.boundParams.low .. prepStmt.boundParams.high:
    if DpiResult(dpiVar_release(prepStmt.boundParams[i].paramVar)).isFailure:
      raise newException(IOError, "destroy: " &
          getErrstr(prepStmt.relatedConn.context.oracleContext))
      {.effects.}
    
  for i in prepStmt.rsOutputCols.low .. prepStmt.rsOutputCols.high:
    if DpiResult(dpiVar_release(prepStmt.rsOutputCols[i].paramVar)).isFailure:
      raise newException(IOError, "destroy: " &
          getErrstr(prepStmt.relatedConn.context.oracleContext))
      {.effects.}
      
  prepStmt.boundParams.setLen(0)
  prepStmt.rsOutputCols.setLen(0)

  if DpiResult(dpiStmt_release(prepStmt.pStmt)).isFailure:
    raise newException(IOError, "destroy: " &
      getErrstr(prepStmt.relatedConn.context.oracleContext))
    {.effects.}

                              
proc executeAndInitResultSet(prepStmt: var PreparedStatement,
                         dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord,
                         isRefCursor: bool ) =
  ## initialises the derived ResultSet
  ## from the given preparedStatement by calling execute on it
  prepStmt.rsMoreRows = true
  prepStmt.rsRowsFetched = 0

  if not isRefCursor:
  # TODO: get rid of quirky isRefCursor flag
    if DpiResult(
           dpiStmt_execute(prepStmt.pStmt,
                           dpiMode,
                           prepStmt.columnCount.addr)
                  ).isFailure:
        raise newException(IOError, "executeAndInitResultSet: " &
                getErrstr(prepStmt.relatedConn.context.oracleContext))
        {.effects.}              
  else:
    discard dpiStmt_getNumQueryColumns(prepStmt.pStmt,
        prepStmt.columnCount.addr)
    if DpiResult(
           dpiStmt_setFetchArraySize(prepStmt.pStmt,
                                     prepStmt.bufferedRows.uint32)
      ).isFailure:
      raise newException(IOError, "executeAndInitResultSet(refcursor): " &
        getErrstr(prepStmt.relatedConn.context.oracleContext))
      {.effects.}

  if prepStmt.rsOutputCols.len <= 0:
    # create the needed buffercolumns(resultset) automatically
    # only once
    prepStmt.rsOutputCols = newParamTypeList(prepStmt.columnCount.int)
    prepStmt.rsColumnNames = newSeq[string](prepStmt.columnCount.int)
    if DpiResult(dpiStmt_getInfo(prepStmt.pStmt, 
                                 prepStmt.statementInfo.addr)).isFailure:
      raise newException(IOError, "executeAndInitResultSet: " &
            getErrstr(prepStmt.relatedConn.context.oracleContext))
      {.effects.}
                          
    var qInfo: dpiQueryInfo
    for i in countup(1, prepStmt.columnCount.int):
      # extract needed params out of the metadata
      # the columnindex starts with 1
      # TODO: if a type is not supported by ODPI-C
      # log error within the ParamType
      if DpiResult(dpiStmt_getQueryInfo(prepStmt.pStmt, 
                                        i.uint32, 
                                        qInfo.addr)).isFailure:
        raise newException(IOError, "executeAndInitResultSet: " &
                          getErrstr(prepStmt.relatedConn.context.oracleContext))
        {.effects.}
                                                                           
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
                          sizeIsBytes: true, 
                          scale: qinfo.typeinfo.scale,
                          name : $qinfo.name,
                          precision : qinfo.typeinfo.precision,
                          fsPrecision : qinfo.typeinfo.fsPrecision
                          ),
                          paramVar: nil,
                          buffer: nil,
                          rowBufferSize: prepStmt.bufferedRows)
                          # each out-resultset param owns the rowbuffersize
                          # of the prepared statement
      newVar(prepStmt,prepStmt.rsOutputCols[i-1])
      if DpiResult(dpiStmt_define(prepStmt.pStmt,
                                  (i).uint32,
                                  prepStmt.rsOutputCols[i-1].paramVar)
                                  ).isFailure:
        raise newException(IOError, "addOutColumn: " & $prepStmt.rsOutputCols[i-1] &
          getErrstr(prepStmt.relatedConn.context.oracleContext))
        {.effects.}
    
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

template resetParamRows(ps : var PreparedStatement) =
  ## resets the parameter rows to the spawned maxrow 
  ## window size of the prepared statement
  for i in ps.boundParams.low .. ps.boundParams.high:
    ps.boundParams[i].rowBufferSize = ps.bufferedRows


template updateBindParams(prepStmt: var PreparedStatement) =
  # reread the params for reexecution of the prepared statement
  for i in prepStmt.boundParams.low .. prepStmt.boundParams.high:
    let bp = prepStmt.boundParams[i]

    if bp.rowBufferSize > 1:
      if DpiResult(dpiVar_setNumElementsInArray(bp.paramVar,
                                           bp.rowBufferSize.uint32)).isFailure:
        raise newException(IOError, "updateBindParams: " &
                            getErrstr(prepStmt.relatedConn.context.oracleContext))
        {.effects.}
                          
    if bp.bindPosition.kind == BindInfoType.byPosition:
      if DpiResult(dpiStmt_bindByPos(prepStmt.pStmt,
                                     bp.bindPosition.paramVal.uint32,
                                     bp.paramVar
        )
      ).isFailure:
        raise newException(IOError, "updateBindParams: " &
                  getErrstr(prepStmt.relatedConn.context.oracleContext))
        {.effects.}

    elif bp.bindPosition.kind == BindInfoType.byName:
      if DpiResult(dpiStmt_bindByName(prepStmt.pStmt,
                                     bp.bindPosition.paramName,
                                     bp.bindPosition.paramName.len.uint32,
                                     bp.paramVar
        )
      ).isFailure:
        raise newException(IOError, "updateBindParams: " &
                         $bp.bindPosition.paramName &
                           getErrstr(prepStmt.relatedConn.context.oracleContext))
        {.effects.}  

template executeStatement*(prepStmt: var PreparedStatement,
                        outRs: var ResultSet,
                        dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord) =
  ## the results can be fetched
  ## on a col by col base. once executed the bound columns can be reused
  ##
  ## multiple dpiMode's can be "or"ed together.
  ## raises IOError in case of an error

  # probe if binds present
  if prepStmt.boundParams.len > 0:
    updateBindParams(prepStmt)

  prepStmt.executeAndInitResultSet(dpiMode,false)
  outRs = cast[ResultSet](prepStmt)

template executeBulkUpdate(prepStmt: var PreparedStatement,
                        numRows: int,
                        dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord) =
  ## executes the statement without returning any rows.
  ## suitable for bulk insert
  if prepStmt.boundParams.len > 0:
    updateBindParams(prepStmt)

  if DpiResult(dpiStmt_executeMany(prepStmt.pStmt,
                                  dpimode,
                                  numRows.uint32)).isFailure:
    raise newException(IOError, "executeMany: " &
           getErrstr(prepStmt.relatedConn.context.oracleContext))
    {.effects.}

template fetchNextRows*(rs: var ResultSet) =
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
        getErrstr(rs.relatedConn.context.oracleContext))
      {.effects.}
  
iterator columnTypesIterator*(rs : var ResultSet) : tuple[idx : int, ct: ColumnType] = 
  ## iterates over the resultSets columnTypes if present
  for i in countup(rs.rsOutputCols.low,rs.rsOutputCols.high):
    yield (i,rs[i].columnType)

iterator resultSetRowIterator*(rs: var ResultSet): DpiRow =
  ## iterates over the resultset row by row. no data copy is performed
  ## and the ptr type values should be copied into the application
  ## domain before the next window is requested.
  ## do not use this iterator in conjunction with fetchNextRows because
  ## it's already used internally.
  ## in an error case an IOException is thrown with the error message retrieved
  ## out of the context.
  var p: DpiRow = DpiRow(rawRow : newSeq[ptr dpiData](rs.rsOutputCols.len), 
                         rSet : rs)
  rs.rsCurrRow = 0
  rs.rsRowsFetched = 0

  fetchNextRows(rs)
  
  while rs.rsCurrRow < rs.rsRowsFetched:
    for i in rs.rsOutputCols.low .. rs.rsOutputCols.high:
      p.rawRow[i] = rs.rsOutputCols[i][rs.rsCurrRow]
      # construct column
    yield p
    inc rs.rsCurrRow
    if rs.rsCurrRow == rs.rsRowsFetched and rs.rsMoreRows:
      fetchNextRows(rs)
      rs.rsCurrRow = 0

iterator bulkBindIterator*(pstmt: var PreparedStatement,
                           rs: var ResultSet,
                           maxRows : int,
                           maxRowBufferWindow : int): 
                              tuple[rowcounter:int,
                                    buffercounter:int] =
  ## convenience iterator for bulk binding.
  ## it will countup to maxRows but will return the next
  ## index of the rowBuffer. maxRowBufferIdx is the high watermark.
  ## if it is reached executeStatement is called automatically
  ## and the internal counter is reset to 0.
  ## both internal counters (maxRows and maxRowBufferWindow) start
  ## with 0 
  if maxRows < maxRowBufferWindow:
    raise newException(IOError,"bulkBindIterator: " &
      "constraint maxRows < maxRowBufferWindow violated " )
    {.effects.}  
  
  if pstmt.bufferedRows < maxRowBufferWindow:
    raise newException(IOError,"bulkBindIterator: " &
      "constraint bufferedRows < maxRowBufferWindow violated. " & 
      " bufferdRows are: " & $pstmt.bufferedRows & " and maxRowBufferWindow" &
      " is: " & $maxRowBufferWindow )
    {.effects.}  

  pstmt.resetParamRows
  # reset the parameter rows to the preparedstatements window

  var rowBufferIdx = 0.int

  for i in countup(0,maxRows):
    yield (rowcounter:i,buffercounter:rowBufferIdx)
    if rowBufferIdx == maxRowBufferWindow:
      # if high watermark reached flush the buffer
      # to db and reset the buffer counter
      pstmt.executeBulkUpdate(maxRowBufferWindow+1)
      rowBufferIdx = 0
    else:
      inc rowBufferIdx                     
  
  if rowBufferIdx > 0:
    # probe if unsent rows present
    pstmt.executeBulkUpdate(rowBufferIdx)

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
          getErrstr(rs.relatedConn.context.oracleContext) )
        {.effects.}
    except:
      discard dpiConn_rollback(dbconn.connection)
      raise


template withPreparedStatement*(ps: var PreparedStatement, body: untyped) =
  ## releases the preparedStatement after leaving
  ## the block.
  # FIXME: prevent nesting
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


proc lookupObjectType*(conn : var OracleConnection,
                       typeName : string) : OracleObjType = 
  ## database-object-type lookup - needed for variable-object-binding.
  ## the returned OracleObjType is always bound to a specific connection.
  ## the typeName can be prefixed with the schemaname the object resides.
  let tname : cstring = $typeName
  result.relatedConn = conn
  if DpiResult(dpiConn_getObjectType(conn.connection,
                                     tname,
                                     tname.len.uint32,
                                     result.baseHdl.addr)).isFailure:
    raise newException(IOError, "lookupObjectType: " &
      getErrstr(conn.context.oracleContext))
    {.effects.}
  var objinfo : dpiObjectTypeInfo  
  if DpiResult(dpiObjectType_getInfo(result.baseHdl,
                                     objinfo.addr)).isFailure:
    raise newException(IOError, "lookupInfoType: " &
                              getErrstr(conn.context.oracleContext))
    {.effects.}
  result.objectTypeInfo = objinfo

  if objinfo.isCollection == 1:
    result.isCollection = true
  else: 
    result.isCollection = false
  
  result.columnTypeList = newSeq[ColumnType](objinfo.numAttributes)
  # setup attribute list

  result.attributes = 
    newSeq[ptr dpiObjectAttr](objinfo.numAttributes)

  if DpiResult(dpiObjectType_getAttributes(
                                           result.baseHdl,
                                           objinfo.numAttributes,
                                           result.attributes[0].addr
  )).isFailure:
    raise newException(IOError, "lookupAttributes: " &
                              getErrstr(conn.context.oracleContext))
    {.effects.}

  var attrInfo : dpiObjectAttrInfo

  for i in result.columnTypeList.low .. result.columnTypeList.high:
    discard dpiObjectAttr_getInfo(result.attributes[i],attrInfo.addr)
    result.columnTypeList[i] = (DpiNativeCType(attrInfo.typeInfo.defaultNativeTypeNum),
                                             DpiOracleType(attrInfo.typeInfo.oracleTypeNum),
                                             attrInfo.typeInfo.clientSizeInBytes.int,
                                             true,
                                             attrInfo.typeInfo.scale,
                                             $attrInfo.name,
                                             attrInfo.typeInfo.precision,
                                             attrInfo.typeInfo.fsPrecision
                                             )
  return result                              
 
proc releaseObjectType( objType : OracleObjType ) = 
  ## releases the object type obtained by lookupObjectType

  # release attributes
  for i in objType.attributes.low .. objType.attributes.high:
    if DpiResult(dpiObjectAttr_release(objType.attributes[i])).isFailure:
      raise newException(IOError, "releaseObjectType: " &
                            getErrstr(objType.relatedConn.context.oracleContext))
      {.effects.}
 
  # release base handle
  if DpiResult(dpiObjectType_release(objType.baseHdl)).isFailure:
    raise newException(IOError, "releaseObjectType: " &
                            getErrstr(objType.relatedConn.context.oracleContext))
    {.effects.}

proc newOracleObject( objType : OracleObjType ) : OracleObj = 
  ## create a new oracle object out of the OracleObjType which can be used
  ## for binding(todo:eval) or reading/fetching from the database.
  if DpiResult(dpiObjectType_createObject(objType.baseHdl,result.objHdl.addr)).isFailure:
     raise newException(IOError, "newOracleObject: " &
       getErrstr(objType.relatedConn.context.oracleContext))
     {.effects.}
  result.objType = objType
  # setup buffered columns
  result.bufferedColumn = newSeq[ptr dpiData](objType.attributes.len)
  var buffbase = cast[int](alloc0(result.bufferedColumn.len * sizeof(dpiData)))
  let dpiSize = sizeof(dpiData)
  for i in result.bufferedColumn.low .. result.bufferedColumn.high:
    result.bufferedColumn[i] = cast[ptr dpiData](buffbase)
    buffbase = buffbase + dpiSize
  # TODO: eval if its better to keep one object values within the type.
  # a large object count would result needs massive memory. the downside
  # would be that the get/fetch templates would not work on instances anymore.
  return result

proc releaseOracleObject( obj : OracleObj ) = 
  ## releases the objects internal references
  dealloc(obj.bufferedColumn[0])
  if DpiResult(dpiObject_release(obj.objHdl)).isFailure:
    raise newException(IOError, "releaseOracleObject: " &
      getErrstr(obj.objType.relatedConn.context.oracleContext))
    {.effects.}


template lookUpAttrIndexByName( obj : OracleObj, attrName : string ) : int =
  ## used by the attributeValue getter/setter to obtain the index by name
  var ctypeidx = -1
  for i in obj.objType.columnTypeList.low .. obj.objType.columnTypeList.high:
    if cmp(attrName, obj.objType.columnTypeList[i].name) == 0:
      ctypeidx = i
      break;
      
  if ctypeidx == -1:
    raise newException(IOError, "lookupAttrIndexByName: " &
          " attrName " & attrName & " not found!")
    {.effects.}
  ctypeidx
    

proc getAttributeValue( obj : var OracleObj, idx : int ) : ptr dpiData = 
  ## getAttributePointer by index as specified in the ColumnTypeList
  let ctype = obj.objType.columnTypeList[idx]
  let attr = obj.objType.attributes[idx]
  
  if DpiResult(dpiObject_getAttributeValue(
                obj.objHdl,
                attr,
                ctype.nativeType.dpiNativeTypeNum,
                obj.bufferedColumn[idx] )
               ).isFailure:
    raise newException(IOError, "getAttributeValue: " &
      getErrstr(obj.objType.relatedConn.context.oracleContext))
    {.effects.}
  
  return obj.bufferedColumn[idx]

proc setAttributeValue( obj : OracleObj, idx: int ) = 
  # the data ptr can be reused after calling the api
  let ctype = obj.objType.columnTypeList[idx]
  let attr = obj.objType.attributes[idx]

  if DpiResult(dpiObject_setAttributeValue(
                obj.objHdl,
                attr,
                ctype.nativeType.dpiNativeTypeNum,
                obj.bufferedColumn[idx])
               ).isFailure:
    raise newException(IOError, "setAttributeValue: " &
      getErrstr(obj.objType.relatedConn.context.oracleContext))
    {.effects.}    

template `[]`*(obj: OracleObj, colidx: int): ptr dpiData =
  getAttributeValue(obj,colidx)

template `[]`*(obj: OracleObj, attrName: string ): ptr dpiData =
  getAttributeValue(obj,lookUpAttrIndexByName(obj,attrName))  


# appendElement with type: object (only possible with collection objects?)
# create the object and call:
#   dpiData_setObject(&data, obj2); sets the object to the data
#   dpiObject_appendElement(obj, DPI_NATIVE_TYPE_OBJECT, &data); 
# to populate a buffer-cell call: dpiVar_setFromObject
#                          dpiVar_getFromObject

proc bindOracleObject(pstmt : var PreparedStatement , obj : var OracleObj ) =
  ## FIXME: implement 
  discard

proc newTempLob*( conn : var OracleConnection, 
                  lobtype : DpiLobType, 
                  outlob : var Lob )  = 
  ## creates a new temp lob
  if DpiResult(dpiConn_newTempLob(conn.connection,
               lobtype.ord.dpiOracleTypeNum,
               addr(outlob.lobref))).isFailure:
    raise newException(IOError, "createConnection: " &
      getErrstr(conn.context.oracleContext))
    {.effects.}

when isMainModule:
  ## the HR Schema is used (XE) for the following tests
  const
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

  newOracleContext(octx,DpiAuthMode.SYSDBA)
  # create the context with authentication Method
  # SYSDBA and default encoding (UTF8)
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
 
  for i,ct in rs.columnTypesIterator:
    echo "cname:" & rs.rsColumnNames[i] & " colnumidx: " & 
      $(i+1) & " " & $ct

  for row in resultSetRowIterator(rs):
    # the result iterator fetches internally further
    # rows if present 
    # example of value retrieval by columnname or index

    echo $row[0].fetchRowId &
    " " & $row[1].fetchDouble &
    " " & $row["FIRST_NAME"].fetchString &
    " " & $row["LAST_NAME"].fetchString &
    " " & $row[10].fetchInt64 &
    " " & $row[11].fetchInt64

  echo "query1 executed - param department_id = 80 "
  # reexecute preparedStatement with a different parameter value
  param.setInt64(some(10.int64))
  executeStatement(pstmt, rs)
  # the parameter is changed here and the query is 
  # re-executed 

  for row in resultSetRowIterator(rs):
    # retrieve column values by columnname or index
    echo $row[0].fetchRowId &
      " " & $row[1].fetchDouble &
      " " & $row["FIRST_NAME"].fetchString &
      " " & $row["LAST_NAME"].fetchString &
      " " & $row[10].fetchInt64 &
      " " & $row[11].fetchInt64
  
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
      echo $row[0].fetchString

    echo "refCursor 2 results: filter with department_id = 80 "

    var refc2 : ResultSet
    pstmt2.openRefCursor("refc2", refc2, 10, DpiModeExec.DEFAULTMODE.ord)

    for row in resultSetRowIterator(refc2):
      echo $row[0].fetchString & " " & $row[1].fetchString

  var ctableq = osql""" CREATE TABLE HR.DEMOTESTTABLE(
                        C1 VARCHAR2(20) NOT NULL 
                      , C2 NUMBER(5,0)
                      , C3 raw(20) 
                      , C4 NUMBER(5,3)
                      , C5 NUMBER(15,5)
                      , C6 TIMESTAMP
                      , CONSTRAINT DEMOTESTTABLE_PK PRIMARY KEY(C1) 
    ) """ 
 
  conn.executeDDL(ctableq) 
  echo "table created"

  var insertStmt: SqlQuery =
    osql""" insert into HR.DEMOTESTTABLE(C1,C2,C3,C4,C5,C6) 
                                values (:1,:2,:3,:4,:5,:6) """

  var pstmt3 : PreparedStatement
  conn.newPreparedStatement(insertStmt, pstmt3, 10)
  # bulk insert example. 21 rows are inserted with a buffer
  # window of 9 and 3 rows. 
  # once the preparedStatement is instanciated - 
  # the buffer row window is fixed and can't resized

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

  pstmt3.withPreparedStatement:
    conn.withTransaction: # commit after this block
      # cleanup of preparedStatement beyond this block
      var varc2 : Option[int64]
      for i,bufferRowIdx in pstmt3.bulkBindIterator(rset,12,8):
        # i: count over 13 entries - with a buffer window of 9 elements
        # if the buffer window is filled
        # contents are flushed to the database.
        if i == 9:
          varc2 = none(int64) # simulate dbNull
        else:
          varc2 = some(i.int64)
        # unfortunately setString/setBytes have a different
        # API than the value-parameter types
        pstmt3[1.BindIdx][bufferRowIdx].setString(some("test_äüö" & $i)) #pk
        pstmt3[2.BindIdx][bufferRowIdx].setInt64(varc2)
        pstmt3[3.BindIdx][bufferRowIdx].setBytes(some(@[(0xAA+i).byte,0xBB,0xCC]))
        pstmt3[4.BindIdx][bufferRowIdx].setFloat(some(i.float32+0.12.float32))
        pstmt3[5.BindIdx][bufferRowIdx].setDouble(some(i.float64+99.12345))
        pstmt3[6.BindIdx][bufferRowIdx].setDateTime(some(getTime().local))
    # example: reuse of preparedStatement and insert another 8 rows
    # with a buffer window of 3 elements 
    conn.withTransaction:
      for i,bufferRowIdx in pstmt3.bulkBindIterator(rset,7,2):
        pstmt3[1.BindIdx][bufferRowIdx].setString(some("test_äüö" & $(i+13))) #pk
        pstmt3[2.BindIdx][bufferRowIdx].setInt64(some(i.int64))
        pstmt3[3.BindIdx][bufferRowIdx].setBytes(none(seq[byte]))   # dbNull
        pstmt3[4.BindIdx][bufferRowIdx].setFloat(none(float32))     # dbNull
        pstmt3[5.BindIdx][bufferRowIdx].setDouble(none(float64))    # dbNull
        pstmt3[6.BindIdx][bufferRowIdx].setDateTime(none(DateTime)) # dbNull



  var selectStmt: SqlQuery = osql"""select c1,c2,rawtohex(c3)
                                         as c3,c4,c5,c6 from hr.demotesttable"""
      # read now the committed stuff

  var pstmt4 : PreparedStatement
  var rset4 : ResultSet

  conn.newPreparedStatement(selectStmt, pstmt4, 5)
  # test with smaller window: 5 rows are buffered internally for reading

  withPreparedStatement(pstmt4): 
    pstmt4.executeStatement(rset4)
    for row in resultSetRowIterator(rset4):       
      echo $row[0].fetchString & "  " & $row[1].fetchInt64 & 
            " " & $row[2].fetchString & 
          # " "  & $fetchFloat(row[3].data) &
          # TODO: eval float32 vals 
            " " & $row[4].fetchDouble & " " & $row[5].fetchDateTime
          # FIXME: fetchFloat returns wrong values / dont work as expected
  echo "finished fetching" 
      # drop the table
  var dropStmt: SqlQuery = osql"drop table hr.demotesttable"
  conn.executeDDL(dropStmt)
    # cleanup - table drop

  var demoInOUT : SqlQuery = osql""" 
     CREATE OR REPLACE FUNCTION HR.DEMO_INOUT 
     (
      PARAM1 IN VARCHAR2, 
      PARAM2 IN OUT NOCOPY VARCHAR2, 
      PARAM3 OUT NOCOPY VARCHAR2
      ) RETURN VARCHAR2 AS
           px1 varchar2(50);
        BEGIN
         if param2 is not null then
          px1 := param1 || '_test_' || param2;
          param3 := param2;
          param2 := px1;
         else
          param3 := 'param2_was_null';
         end if;
      RETURN 'FUNCTION_DEMO_INOUT_CALLED';
    END DEMO_INOUT;
     """

  conn.executeDDL(demoInOut)
  # incarnate function

  var demoCallFunc = osql"""begin :1 := HR.DEMO_INOUT(:2, :3, :4); end; """
  # :1 result variable type varchar2
  # :2 in variable type varchar2
  # :3 inout variable type varchar2
  # :4 out variable type varchar2
  var callFunc : PreparedStatement
  var callFuncResult : ResultSet
  newPreparedStatement(conn,demoCallFunc,callFunc)
  
  withPreparedStatement(callFunc):
    # call the function with direct parameter access 
    let param1 = callFunc.addBindParameter(newStringColTypeParam(50),BindIdx(1))
    let param2 = callFunc.addBindParameter(newStringColTypeParam(20),BindIdx(2))
    let param3 = callFunc.addBindParameter(newStringColTypeParam(20),BindIdx(3))
    let param4 = callFunc.addBindParameter(newStringColTypeParam(20),BindIdx(4))
    # direct param access in this example
    param2.setString(some("teststr äüö")) 
    param3.setString(some("p2"))
    callFunc.executeStatement(callFuncResult) 
    var r1 = param1.fetchString()
    # fetch functions result
    var r3 = param3.fetchString()
    # fetch functions inout var
    var r4 = param4.fetchString()
    # fetch functions out var

    echo "param :1 (result) = " & r1.get
    if r3.isSome:
      echo "param :3 (inout) = " & r3.get
    echo "param :4 (out) = " & r4.get

  var cleanupDemo : SqlQuery = osql" drop function hr.demo_inout "
  conn.executeDDL(cleanupDemo)

  # lookup object-type
  var demoCreateObj : SqlQuery = osql"""
    create or replace type HR.DEMO_OBJ FORCE as object (
      NumberValue                         number(15,8),
      StringValue                         varchar2(60),
      FixedCharValue                      char(10),
      DateValue                           date,
      TimestampValue                      timestamp 
    );
   """
  conn.executeDDL(demoCreateObj)

  # lookup type and print results
  let objtype = conn.lookupObjectType("HR.DEMO_OBJ")
  var obj  = objtype.newOracleObject
 
  obj[0].setDouble(some(100.float64))
  setAttributeValue(obj,0) # updates attribute to odpi-c

  echo $(obj[0].fetchDouble) # value from buffer
  echo $getAttributeValue(obj,0).fetchDouble # value from odpi-c
  
  objtype.releaseObjectType

  var dropDemoObj : SqlQuery = osql" drop type HR.DEMO_OBJ "
  conn.executeDDL(dropDemoObj)


  conn.releaseConnection
  destroyOracleContext(octx)
