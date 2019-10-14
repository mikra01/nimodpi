import os
import times
import typeinfo
import options
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
    - resultset zero-copy approach: the caller is responsible for copying the data
    - (helper templates present)
    - within the application domain. "peeking" data is possible via pointers
    - only the basic types are implemented (numeric, rowid, varchar2, timestamp)
    - pl/sql procedure exploitation is possible with in/out and inout-parameters
    - consuming refcursor is also possible (see demo.nim)
    - TODO: implement LOB/BLOB handling
    -
    - designing a vendor generic database API often leads to clumpsy workaround solutions.
      due to that it's out of scope of this project. it's more valueable to wrap the vendor
      specific parts into a own module with a question/answer style API according to the business-case
    -
    - besides the connections there are three basic important objects:
    - ParamType is used for parameter binding (in/out/inout) and consuming result columns
    - PreparedStatement is used for executing dml/ddl with or without parameters. internal resources
    - are not freed unless destroy is called.
    - ResultSets are used to consume query results and can be reused (WIP)
    - it provides a row-iterator-style
    - API and a direct access API of the buffer (by index)
    -
    - some additional hints: do not share connection/preparedStatement between different threads. 
    - the context can be shared between threads according to the ODPI-C documentation (untested).
    - index-access of a resultset is not bounds checked.
    - if a internal error happens, execution is terminated and the cause could be extracted with the
    - template getErrstr out of the context.
    - the API does not prevent misuse actually. 
    -
    - for testing and development the XE database is sufficient.
    - version 18c also supports partitioning, PDB's and so on.
    -
    - database resident connection pool is not tested but should work
    -
    - TODO: more types,bulk binds, implement tooling for easier sqlplus exploitaition,
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

  BindIdx = distinct range[1.int .. int.high ]
 
  BindInfoType = enum byPosition, byName

  BindInfo = object
    # tracks the bindType. 
    case kind*: BindInfoType
      of byPosition: paramVal*: BindIdx
      of byName: paramName*: cstring

  ParamType* = object
    ## describes how the database type is mapped onto
    ## the database type.
    bindPosition*: BindInfo
    queryInfo: dpiQueryInfo
    columnType*: ColumnType
    # tracks the native- and dbtype
    paramVar: ptr dpiVar
    buffer: ptr dpiData
    rowBufferSize: int   
    # number of buffered rows
    ## for single parameters always 1 - for columnar parameters > 1 up to
    ## the given arraySize

  ParamTypeRef* = ref ParamType

  ParamTypeList* = seq[ParamTypeRef]

  ColumnType* = tuple[nativeType: DpiNativeCType, 
                      dbType: DpiOracleType, 
                      colsize: int,
                      sizeIsBytes : bool,
                      scale : int] # scale only for numeric types recognised
  ColumnTypeList* = seq[ColumnType]

  # use dpiStmt_executeMany for bulk binds

  SqlQuery* = object
    ## fixme: use sqlquery from db_common
    rawSql: cstring

  PreparedStatement* = object
    relatedConn: OracleConnection
    query*: SqlQuery
    boundParams: ParamTypeList      # mixed in/out or inout
    stmtCacheKey*: cstring
    scrollable: bool            # unused
    executed: bool              # quirky flag used to track the state
    columnCount: uint32         # deprecated
                                # fetchArraySize : int
    pStmt: ptr dpiStmt
    statementInfo*: dpiStmtInfo # populated within execute stage
                                # following members are resultset related
    rsOutputCols: ParamTypeList
    rsCurrRow*: int             # reserved for iterating
    rsMoreRows*: bool           #
    rsBufferRowIndex*: int
    rsRowsFetched*: int
    rsBufferedRows*: int        # refers to the maxArraySize
    rsColumnNames*: seq[string] # todo: implement

  ResultSet* = PreparedStatement
  # type alias

  DpiRowElement* = tuple[ columnType : ColumnType, data : ptr dpiData  ]
  DpiRow* = seq[DpiRowElement]

include odpi_obj2string
include odpi_to_nimtype

template `[]`*(data: ptr dpiData, idx: int): ptr dpiData =
  ## direct access of the cell(row) within the columnbuffer by index
  cast[ptr dpiData]((cast[int](data)) + (sizeof(dpiData)*idx))

template `[]`*(rs: var ResultSet, colidx: int): ParamTypeRef =
  ## selects the column of the resultSet.
  rs.rsOutputCols[colidx]
 
template `[]`*(rs: var ParamTypeRef, rowidx: int): ptr dpiData =
  ## selects the row of the specified column
  ## the value could be extracted by the dpiData/dpiDataBuffer ODPI-C API
  ## or with the fetch-templates 
  ##
  ## further reading:
  ## https://oracle.github.io/odpi/doc/structs/dpiData.html
  cast[ptr dpiData]((cast[int](rs.buffer)) + (sizeof(dpiData)*rowidx))

template `[]`*(rs: var PreparedStatement, bindidx: BindIdx): ParamTypeRef =
  # retrieves the paramType for setting the parameter value by index
  # use the setParam templates for setting the value after that.
  # before fetching make sure that the parameter is already created
  for i in rs.boundParams.low .. rs.boundParams.high:
    if not rs.boundParams[i].isNil:
      if rs.boundParams[i].bindPosition.kind == byPosition:
        if rs.boundParams[i].bindPosition.paramVal == bindidx:
          result = rs.boundParams[i]
          return result
  
  raise newException(IOError, "PreparedStatement[] parameterIdx : " & $bindidx & " not found!" )
  {.effects.}
        
template `[]`*(rs: var PreparedStatement, paramName: string): ParamTypeRef =
  # retrieves the pointer for setting the parameter value by paramname
  # before fetching make sure that the parameter is already created otherwise
  # an IOError is thrown
  for i in rs.boundParams.low .. rs.boundParams.high:
    if not rs.boundParams[i].isNil:
      if rs.boundParams[i].bindPosition.kind == byName:
        if cmp(paramName,rs.boundParams[i].bindPosition.paramName) == 0:
          result = rs.boundParams[i]
          return result

  raise newException(IOError, "PreparedStatement[] parameter : " & paramName & " not found!" )
  {.effects.}
  
template isDbNull*(val : ptr dpiData) : bool =
  ## returns true if the value is dbNull (value not present)
  val.isNull.bool

template setDbNull*(val : ptr dpiData)  =
  ## sets the value to dbNull (no value present)
  val.isNull = 1.cint  

template setNotDbNull*(val : ptr dpiData)  =
  ## sets value present
  val.isNull = 0.cint  
  
template fetchBoolean*(val : ptr dpiData) : Option[bool] =
  ## fetches the specified value as boolean. the value is copied
  if val.isDbNull:
    none(bool)
  else:
    some(val.value.asBoolean)

template setBoolean*(param : ParamTypeRef, value : Option[bool] ) =
  ## bind parameter setter boolean type. this setter operates always with index 1
  if value.isNone:
     param.buffer.setDbNull
  else:
     param.buffer.setNotDbNull  
     param.buffer.asBoolean.value = value.some  
  
# simple type conversion templates.
template fetchFloat*(val : ptr dpiData) : Option[float32] =
  ## fetches the specified value as float. the value is copied 
  if val.isDbNull:
    none(float32)
  else:
    some(val.value.asFloat.float32)

template setFloat*( param : ParamTypeRef, value : Option[float32]) =
  ## bind parameter setter float32 type. this setter operates always with index 1
  if value.isNone:
    param.buffer.setDbNull
  else:
    param.buffer.setNotDbNull  
    param.buffer.asFloat.value = value.some

template fetchDouble*(val : ptr dpiData) : Option[float64] =
  ## fetches the specified value as double (Nims 64 bit type). the value is copied 
  if val.isDbNull:
    none(float64)
  else:
    some(val.value.asDouble.float64)

template setDouble*(param : ParamTypeRef, value : Option[float64]) =
  ## bind parameter setter float64 type. this setter operates always with index 1
  if value.isNone:
    param.buffer.setDbNull
  else:  
    param.buffer.setNotDbNull
    param.buffer.asDouble = value.some   
  
template fetchUInt64*(val : ptr dpiData) : Option[uint64] =
  ## fetches the specified value as double (Nims 64 bit type). the value is copied 
  if val.isDbNull:
    none(uint64)
  else:
    some(val.value.asUint64)

template setUInt64*(param : ParamTypeRef, value : Option[uint64]) =
  ## bind parameter setter uint64 type. this setter operates always with index 1
  if value.isNone:
    param.buffer.setDbNull
  else:
    param.buffer.setNotDbNull  
    param.buffer.asUint64 = value.some    
      
template fetchInt64*(val : ptr dpiData) : Option[int64] =
  ## fetches the specified value as double (Nims 64 bit type). the value is copied 
  if val.isDbNull:
    none(int64)
  else:
    some(val.value.asInt64)

proc setInt64( param : ParamTypeRef, value : Option[int64]) =
   ## bind parameter setter int64 type. this setter operates always with index 1
   if value.isNone:
     param.buffer.setDbNull
   else:  
     param.buffer.setNotDbNull
     param.buffer.value.asInt64  = value.get   

template fetchIntervalDS*(val : ptr dpiData ) : Option[Duration] =
  # todo: implement
  if val.isDbNull:
    none(Duration)
  else:
    some(val.toIntervalDs)
   

template setIntervalDS*(param : ParamTypeRef , value : Option[Duration]) =
  ## bind parameter setter IntervalDS type. this setter operates always with index 1
  if value.isNone:
    param.buffer.setDbNull
  else:  
    param.buffer.setNotDbNull
    param.buffer.value.asIntervalDS.fseconds = value.some.nanoseconds    
    param.buffer.value.asIntervalDS.seconds = value.some.seconds 
    param.buffer.value.asIntervalDS.minutes = value.some.minutes
    param.buffer.value.asIntervalDS.hours = value.some.hours
    param.buffer.value.asIntervalDS.days = value.some.days
  
template fetchDateTime*( val : ptr dpiData ) : Option[DateTime] =
  ## fetches the specified value as DateTime. the value is copied 
  if val.isDbNull:
    none(DateTime)
  else:
    some(toDateTime(val))

template setDateTime*(param : ParamTypeRef , value : Option[DateTime] ) = 
  ## bind parameter setter DateTime type. this setter operates always with index 1
  if value.isNone:
    param.buffer.setDbNull
  else:
    param.buffer.setNotDbNull  
    let dt = cast[DateTime](some)
    let utcoffset = dt.utcOffset
    param.buffer.value.asTimestamp.year = dt.year
    param.buffer.v alue.asTimestamp.month = dt.month     
    param.buffer.value.asTimestamp.day = dt.day
    param.buffer.value.asTimestamp.hour = dt.hour
    param.buffer.value.asTimestamp.minute = dt.minute
    param.buffer.value.asTimestamp.second =  dt.second
    param.buffer.value.asTimestamp.fsecond = dt.nanosecond
    
    if not tz.isNil:
      let tzhour : uint8 =  cast[uint8](utcoffset/3600) # get hours and throw fraction away
      param.buffer.value.asTimestamp.tzHourOffset = tzhour
      param.buffer.value.asTimestamp.tzMinuteOffset = cast[uint8]((utcoffset - tzhour*3600)/60)
      # TODO: eval if ok 
  
template fetchString*( val : ptr dpiData ) : Option[string] =
  ## fetches the specified value as string. the value is copied  
  if val.isDbNull:
    none(string)
  else:
    some(toNimString(val))

template setString*(param : ParamTypeRef , value : Option[string] ) = 
  ## bind parameter setter string type. this setter operates always with index 1
  if value.isNone:
    param.buffer.setDbNull
  else: 
    param.buffer.setNotDbNull 
    discard dpiVar_setFromBytes(param.paramVar,0,addr(value.some[0]),value.some.len)    
  
template fetchBytes*( val : ptr dpiData ) : Option[seq[byte]] =
  ## fetches the specified value as seq[byte]. the byte array is copied
  if val.isDbNull:
    none(seq[byte])
  else:
    some(toNimByteSeq(val))

template setBytes*(param : ParamTypeRef , value: Option[seq[byte]] ) = 
  ## bind parameter setter seq[byte] type. this setter operates always with index 1
  ## the value is copied into the drivers domain 
  if value.isNone:
    param.data.setDbNull
  else:
    param.buffer.setNotDbNull  
    discard dpiVar_setFromBytes(param.paramVar,0,addr(value.some[0]),value.some.len)    
  
template fetchRowId*( param : ptr dpiData ) : ptr dpiRowid =
  ## fetches the rowId (internal representation).
  param.value.asRowId 

template setRowId*(param : ParamTypeRef , rowid : ptr dpiRowid ) =
  ## bind parameter setter boolean type. this setter operates always with index 1
  ## (todo: eval if the rowid could be nil)
  if value.isNone:
    param.data.setDbNull
  else:  
    param.buffer.setNotDbNull
    discard dpiVar_setFromRowid(param.paramVar,0,rowid)  

template getColumnCount*( rs : var ResultSet) : int =
  ## returns the number of columns for the ResultSet
  rs.rsColumnNames.len  
  
proc getColumnTypeList*( rs : var ResultSet) : ColumnTypeList =
  result = newSeq[ColumnType](rs.getColumnCount) 
  for i in result.low .. result.high:
    result[i] = rs[i].columnType 

template getNativeType*(pt: var ParamTypeRef): DpiNativeCType =
  ## peeks the native type of a param. useful to determine
  ## which type the result column would be
  pt.nativeType

template getDbType*(pt : var ParamTypeRef): DpiOracleType =
  ## peeks the db type of the given param
  pt.dbType

template newParamTypeList(len: int): ParamTypeList =
  # internal template ParamTypeList construction
  newSeq[ParamTypeRef](len)

proc newSqlQuery*(sql: string): SqlQuery =
  ## template to construct a SqlQuery type
  SqlQuery(rawSql: sql.cstring)

proc newOracleContext*(encoding: NlsLang, authMode: DpiAuthMode,
                       outCtx: var OracleContext,
                           outMsg: var string): DpiResult =
  ## constructs a new OracleContext needed to access the database.
  ## if DpiResult.SUCCESS is returned the outCtx is populated. 
  ## In case of an error outMsg
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
  # TODO: evaluate what happens if there are open connections present
  result = DpiResult(dpiContext_destroy(ocontext.oracleContext))

template getErrstr*(ocontext: var OracleContext): string =
  ## checks if the last operation results with error or not
  var ei: dpiErrorInfo
  dpiContext_getError(ocontext.oracleContext, ei.addr)
  $ei

template isSuccess*(result: DpiResult): bool =
  result == DpiResult.SUCCESS

template onSuccessExecute(context: ptr dpiContext, toprobe: untyped,
    body: untyped) =
  ## template to wrap the boilerplate errorinfo code.
  ## used for the tests 
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
  ## creates a connection for the given context and credentials. 
  ## use getErrstr to retrieve
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

proc newPreparedStatement*(conn: var OracleConnection, 
                           query: var SqlQuery,
                           outPs: var PreparedStatement,
                           stmtCacheKey: string = "" ): DpiResult =
  ## constructs a new prepared statement object linked to the given specified query.
  ## the statement cache key is optional.
  outPs.scrollable = false # always false due to not implemented
  outPs.query = query
  outPs.columnCount = 0
  outPs.relatedConn = conn
  outPs.executed = false
  outPs.stmtCacheKey = stmtCacheKey.cstring
  outPs.boundParams = newSeq[ParamTypeRef](0)
  result = DpiResult(dpiConn_prepareStmt(conn.connection, 0.cint, query.rawSql,
      query.rawSql.len.uint32, outPs.stmtCacheKey,
      outPs.stmtCacheKey.len.uint32, outPs.pStmt.addr))

template bindParameter(ps: var PreparedStatement, param: ParamTypeRef) =
  # internal proc which is processed after the param is completely populated
  var isArray: uint32 = 0
  if param.rowBufferSize > 1:
    isArray = 1

  discard dpiConn_newVar(
         ps.relatedConn.connection,
         cast[dpiOracleTypeNum](param.columnType.dbType.ord),
         cast[dpiNativeTypeNum](param.columnType.nativeType.ord),
         param.rowBufferSize.uint32, #maxArraySize
      param.columnType.colsize.uint32, #size
      param.columnType.sizeIsBytes.cint, #sizeIsBytes
      isArray.cint, # isArray
      nil,
      param.paramVar.addr,
      param.buffer.addr
      )

template isParamPresent(ps : var PreparedStatement, paramName : string) : bool =
  discard # TODO: implement

template isParamPresent(ps : var PreparedStatement, paramIdx: BindIdx) : bool =
  discard # TODO: implement

template newColumnType*( nativeType : DpiNativeCType, 
                     dbType: DpiOracleType, 
                     colsize : int = 1, 
                     sizeIsBytes: bool = false  ) : ColumnType =
  ## construction proc for the ColumnType type. for numerical types colsize is always 1.
  ## only for varchars,blobs the colsize must be set (max). if sizeIsBytes is false,
  ## the colsize must contain the number of characters not the bytecount.
  ## TODO: templates for basic nim types                     
  (nativeType : nativeType,dbType : dbType, colsize: colsize, sizeIsBytes:sizeIsBytes)  

proc addBindParameter*(ps : var PreparedStatement, 
                         coltype : ColumnType,  
                         paramName : string, 
                         rowCount : int = 1) : ParamTypeRef =
  ## creates a bindparameter by parameterName. the parametername must be referenced within the
  ## query by :<paramName>
  ## the parameter value can be set with the typed setters on the ParamType.
  ## see https://oracle.github.io/odpi/doc/user_guide/data_types.html for supported type
  ## combinations.
  ## the type of the parameter can be in,out or in/out
  # todo: use template bindparameter
  # call bindBy only after the value is set.
  result = ParamTypeRef( bindPosition: BindInfo(kind: BindInfoType.byName,
                                                   paramName: paramName),
                              columnType: coltype,
                              paramVar: nil,
                              buffer: nil,
                              rowBufferSize: rowCount)
  bindParameter(ps,result)
  ps.boundParams.add(result)                            

proc addBindParameter*(ps : var PreparedStatement, 
                         coltype : ColumnType, 
                         idx : BindIdx, 
                         rowCount : int = 1) : ParamTypeRef =
  ## creates a bindparameter by parameter index. the parameterindex must be referenced
  ## within the query with :<paramIndex>.
  ## the parameter value can be set with the typed setters on the ParamType.
  ## see https://oracle.github.io/odpi/doc/user_guide/data_types.html for supported type
  ## combinations.
  ## the type of the parameter can be in, out or in/out
  # todo: use template bindParameter
  # cast[ParamType]new ParamType()
  result = ParamTypeRef( bindPosition: BindInfo(kind: BindInfoType.byPosition,
                         paramVal: idx),
                         columnType: coltype,
                         paramVar: nil,
                         buffer: nil,
                         rowBufferSize: rowCount)
  bindParameter(ps,result)
  ps.boundParams.add(result)                            


proc addOutColumn(rs: var ResultSet, columnParam: ParamTypeRef) =
  ## binds out-parameters to the specified resultset according to the
  ## metadata given by the database
  var isArray: uint32 = 0
  let index: int = columnParam.bindPosition.paramVal.int-1
  # adjust index to nimIndex
  if rs.rsBufferedRows > 1:
    isArray = 1
  rs.rsOutputCols[index] = columnParam

  var paramVar: ptr dpiVar
  var paramBuff: ptr dpiData
  discard DpiResult(
      dpiConn_newVar(
         rs.relatedConn.connection,
         cast[dpiOracleTypeNum](rs.rsOutputCols[index].columnType.dbType.ord),
         cast[dpiNativeTypeNum](rs.rsOutputCols[index].columnType.nativeType.ord),
         rs.rsBufferedRows.uint32, #fetchArraySize
         rs.rsOutputCols[index].columnType.colsize.uint32, #size
         rs.rsOutputCols[index].columnType.sizeIsBytes.cint, #sizeIsBytes
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
  ## the results can be fetched
  ## on a col by col base. once executed the bound columns can be reused
  ##
  ## multiple dpiMode's can be "or"ed together
  
  # probe if binds present
  if prepStmt.boundParams.len > 0:
    for i in prepStmt.boundParams.low .. prepStmt.boundParams.high:
      let bp = prepStmt.boundParams[i]
      if bp.rowBufferSize > 1:
        discard dpiVar_setNumElementsInArray(bp.paramVar,
                                             bp.rowBufferSize.uint32)
      
      if bp.bindPosition.kind == BindInfoType.byPosition:
        discard DpiResult(dpiStmt_bindByPos(prepStmt.pStmt,
                                         bp.bindPosition.paramVal.uint32,
                                         bp.paramVar
                                        )
                     )
      elif bp.bindPosition.kind == BindInfoType.byName:
        discard DpiResult(dpiStmt_bindByName(prepStmt.pStmt,
                                         bp.bindPosition.paramName,
                                         bp.bindPosition.paramName.len.uint32,
                                         bp.paramVar
                                        )
                      )

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
        outRs.rsOutputCols = newParamTypeList(prepStmt.columnCount.int)
        outRs.rsColumnNames = newSeq[string](prepStmt.columnCount.int)
        discard dpiStmt_getInfo(prepStmt.pStmt, prepStmt.statementInfo.addr)
        var qInfo: dpiQueryInfo

        for i in countup(1, prepStmt.columnCount.int):
          # extract needed params out of the metadata
          # the columnindex starts with 1
          # TODO: if a type is not supported by ODPI-C log error within the ParamType
          discard dpiStmt_getQueryInfo(prepStmt.pStmt, i.uint32, qInfo.addr)
          var colname = newString(qInfo.nameLength)
          copyMem(addr(colname[0]), qInfo.name.ptr, colname.len)

          outRs.rsColumnNames[i-1] = colname
          outRs.rsOutputCols[i-1] = ParamTypeRef(
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
                              rowBufferSize: outRs.rsBufferedRows)
          addOutColumn(outRs, outRs.rsOutputCols[i-1])
  else:
    result = DpiResult(DpiResult.FAILURE.ord)

proc fetchNextRows*(rs: var ResultSet): DpiResult =
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
  ## domain before calling fetchNextRows again. value types are copied by assignment
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
  ## and the ptr type values should be copied into the application
  ## domain before the next window is requested.
  ## do not use this iterator in conjunction with fetchNextRows because
  ## it's used internally.
  ## in an error case an IOException is thrown with the error message retrieved
  ## out of the context.
  var p: DpiRow = newSeq[DpiRowElement](rs.rsOutputCols.len)
  var paramtypes = rs.getColumnTypeList
  rs.rsCurrRow = 0

  if rs.rsRowsFetched == 0:
    if fetchNextRows(rs) != DpiResult.SUCCESS:
      raise newException(IOError, "resultSetRowIterator: " & 
        getErrstr(rs.relatedConn.context) )
      {.effects.}
  while rs.rsCurrRow < rs.rsRowsFetched:
    for i in rs.rsOutputCols.low .. rs.rsOutputCols.high:
      p[i] = (columnType : paramtypes[i],
              data : rs.rsOutputCols[i][rs.rsCurrRow])
      # construct column
    yield p
    inc rs.rsCurrRow
    if rs.rsCurrRow == rs.rsRowsFetched and rs.rsMoreRows:
      if fetchNextRows(rs) != DpiResult.SUCCESS:
        raise newException(IOError, "resultSetRowIterator: " & 
          getErrstr(rs.relatedConn.context) )
        {.effects.}         
      rs.rsCurrRow = 0


when isMainModule: 
  ## the HR Schema is used (XE) for the following tests
  const
    lang: NlsLang = "WE8ISO8859P15".NlsLang
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

  if isSuccess(newOracleContext(lang, DpiAuthMode.SYSDBA, octx, errmsg)):

    var conn: OracleConnection

    if isSuccess(createConnection(octx, connectionstr, oracleuser, pw, conn)):

      var query: SqlQuery = newSqlQuery("""select 100 as col1, 'äöü' as col2 from dual 
          union all  
          select 200 , 'äöü2' from dual
          union all
          select 300 , 'äöü3' from dual
          """)

      var query2: SqlQuery = newSqlQuery("""select 
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
       from hr.employees where department_id = :param1  """)
    
      var pstmt: PreparedStatement

      if isSuccess(newPreparedStatement(conn, query2, pstmt)):
        var rs: ResultSet

        addBindParameter(pstmt,
          (DpiNativeCType.INT64,DpiOracleType.OTNUMBER,1,false,1),
          "param1").setInt64(some(80.int64))

        if isSuccess(executeStatement(pstmt, rs, 10)):
          var ctl : ColumnTypeList = rs.getColumnTypeList

          for i in ctl.low .. ctl.high:
            echo "cname:" & rs.rsColumnNames[i] & " colnumidx: " & $(i+1) & " " & $ctl[i]
 
          echo "colcount: " & $rs.rsColumnNames.len
        
          # TODO: generic variable fetching
          echo rs.rsColumnNames[1] & " " & rs.rsColumnNames[2]

          for row in resultSetRowIterator(rs):
            # output first three and last two columns
           echo $fetchRowId(row[0].data) &
             " " & $fetchDouble(row[1].data) & 
                 " " & $fetchString(row[2].data) &
                 " " & $fetchInt64(row[10].data) &
                 " " & $fetchInt64(row[11].data)
        
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

