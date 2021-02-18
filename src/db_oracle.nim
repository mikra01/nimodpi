import os,times,options,strformat,tables
import nimodpi
export nimodpi

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
    - within the application domain. "peeking" data is possible via pointers.
    - copy takes place into odpi-c domain when bindparameter or inserts are used.
    - 
    - 
    - only the basic types are implemented (numeric, rowid, varchar2, timestamp)
    - pl/sql procedure exploitation is possible with in/out and inout-parameters
    - consuming refcursor (out) is also possible (see examples at the end of the file)
    - TODO: implement LOB/BLOB handling
    -
    - designing a vendor generic database API often leads to
      clumpsy workaround solutions.
      due to that a generic API is out of scope of this project.
      it's more valueable to wrap the vendor
      specific parts into an own module with a
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
    - if an internal error happens, execution is terminated
      and the cause could be extracted with the
    - template getErrstr out of the context.
    -
    - for testing and development the XE database is sufficient.
    - version 18c also supports partitioning, PDB's and so on.
    -
    - database resident connection pool is not tested but should work
    - 
    - some definitions: 
    - read operation is database->client direction.
    - write operation is client -> database direction.
    - 
    - TODO:
      * move object related API into own module 
      * object type API needs to be reviewed (resultset/binds) (at the
        moment the object type needs to be specified for resultset obj access) 
        and the API itself is not easy enough.
      * implement tooling for easier sqlplus exploitaition
      * tooling for easy compiletime-query validation,
        continous query notification, examples
    ]#

type
  OracleContext* = object
    ## stateless wrapper for the context and createParams
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
  ## bind parameter type 
  BindInfoType = enum byPosition, byName
  ## bind parameter info type
  
  BindInfo = object
    # tracks the bindType.
    case kind*: BindInfoType
      of byPosition: paramVal*: BindIdx
      of byName: paramName*: string
  ## bind parameter info type. tracks the bindInfoType
  ## and contains either the BindIndexValue (paramVal) 
  ## or the BindParameterName (paramName)

  ColumnType* = tuple[nativeType: DpiNativeCType,
                      dbType: DpiOracleType,
                      colsize: int,
                      sizeIsBytes: bool,
                      scale: int8,
                      name : string,
                      precision : int16,
                      fsPrecision : uint8 ] # scale used for some numeric types
  # FIXME: refactor to object and/or recycle driver type directly
  ColumnTypeList* = seq[ColumnType]

  OracleObjTypeRef* = ref object 
    ## thin wrapper for the object type database handle.
    ## these type of objects need to be disposed if no longer needed.
    ## used for read or write operations for both types and collections.
    relatedConn : OracleConnection
    baseHdl : ptr dpiObjectType
    objectTypeInfo : dpiObjectTypeInfo
    isCollection : bool
    elementDataTypeInfo : ptr dpiDataTypeInfo
    elementObjectTypeInfo : ptr dpiObjectTypeInfo
    # the type of the collections member
    # elementDataTypeInfo and elementObjectTypeInfo only valid
    # for collection types
    childObjectType : OracleObjTypeRef
    # only set if the objectType is a collection
    attributes : seq[ptr dpiObjectAttr]
    # only populated if the type is not a collection
    columnTypeList : ColumnTypeList
    # columnTypeList and attributes are in the
    # same order (for non collection types)
    namedColumnTypes : TableRef[string,OracleObjTypeRef]
    # in case of a object column type the column name refers
    # to the introspected objectType 
    tmpAttrData : ptr dpiData
    # allocated area for fetching/setting attributes
    # by dpiObject handle 
    # FIXME: remove - bind data handles related to the 
    # object and not the object type


  ParamType* = object
    ## ParameterType. describes how the database type is mapped onto
    ## the query
    bindPosition*: BindInfo
    # bind position and type -> rename 2 bindinfo
    queryInfo: dpiQueryInfo
    # populated for returning statements
    columnType*: ColumnType
    # tracks the native- and dbtype
    objectTypeHandle : ptr dpiObjectType
    # object type handle for plsql types
    # used for in/out/inout parameter bind values
    # freed automatically beecause owner is dpiQueryInfo
    rObjTypeInfo : ptr dpiObjectTypeInfo
    # result object type info - only populated 
    # for result parameters at the moment
    rAttributeHdl : seq[ptr dpiObjectAttr]
    # result attribute handle
    # needed for reading/writing object attributes
    rObjectTypeRef : OracleObjTypeRef
    # new objecttype handle for reading/writing objects
    paramVar: ptr dpiVar
    # ODPI-C ptr to the variable def
    buffer: ptr dpiData
    # ODPI-C ptr to the variables data buffer
    # provided by ODPI-C
    rowBufferSize: int
    isPlSqlArray: bool
    isFetched: bool
    # flag used for refcursor reexecute prevention.
    # if a refcursor is within the statement it can't be reused
 
  ParamTypeRef* = ref ParamType
    ## handle to the param type

  ParamTypeList* = seq[ParamTypeRef]

const
  NlsLangDefault = "UTF8".NlsLang
  RefCursorColumnTypeParam* = (DpiNativeCType.STMT,
                               DpiOracleType.OTSTMT,
                               1, false, 1.int8,"",0.int16,0.uint8).ColumnType
  ## predefined parameter for refcursor                                 
  Int64ColumnTypeParam* = (DpiNativeCType.INT64,
                           DpiOracleType.OTNUMBER,
                           1, false, 1.int8,"",0.int16,0.uint8).ColumnType
  ## predefined parameter for the Int64 column type (OTNUMBER)
  FloatColumnTypeParam* = (DpiNativeCType.FLOAT,
                           DpiOracleType.OTNATIVE_FLOAT,
                           1,false,0.int8,"",0.int16,0.uint8).ColumnType
  ## predefined parameter for the Float column type (OTNATIVE_FLOAT)
  DoubleColumnTypeParam* = ( DpiNativeCType.DOUBLE,
                           DpiOracleType.OTNATIVE_DOUBLE,
                           1,false,0.int8,"",0.int16,0.uint8).ColumnType
  ## predefined parameter for the Double column type (OTNATIVE_DOUBLE)
  ZonedTimestampTypeParam* = (DpiNativeCType.TIMESTAMP,
                            DpiOracleType.OTTIMESTAMP_TZ,
                            1,false,0.int8,"",0.int16,0.uint8).ColumnType
  ## predefined parameter for the Timestamp with Timezone type (OTTIMESTAMP_TZ)
  # FIXME: populate scale, precision for fp-types                                                   

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
    # auto-introspected list for returning statements
    rsCurrRow*: int # reserved for iterating
    rsMoreRows*: bool #
    rsBufferRowIndex*: int 
    # ODPI-C pointer type - unused at the moment
    rsRowsFetched*: int # stats counter
    rsColumnNames*: seq[string] 
    # populated on the first executeStatement
  ## PreparedStatement is used for both read and write operations
  ## (working with queries and object types).  

  ResultSet* = PreparedStatement
  ## PreparedStatement type alias

  DpiRow* = object
    rset : ptr ResultSet 
    rawRow : seq[ptr dpiData]
    ## contains all data pointers of the current iterated row
    ## of the ResultSet

  OracleObjRef* = ref object of RootObj
    ## thin wrapper of an object instance
    ## related to a specific type handle. this kind of
    ## object need to be disposed if no longer needed.
    ## typically used for both write and operations (client->database).
    objType : OracleObjTypeRef
    objHdl : ptr dpiObject
    # the odpi-c object handle. this ref needs to be freed if no
    # longer in use
    # paramVar : ptr dpiVar
    dataHelper : ptr dpiData
    # helper used for adding to collection
    bufferedColumn : seq[ptr dpiData]
    # the attributes of the object. only
    # initialized if object owns attributes
    # FIXME: evaluate if needed
    bufferedBytesTypeBase : ptr byte
   
  OracleCollectionRef* = ref object of OracleObjRef
    ## thin wrapper of a collection type element.
    ## this kind of object need to be disposed if no
    ## longer needed.
    elementHelper : ptr dpiData
    # one dpiData chunk 
    # moved to typedef
    incarnatedChilds : TableRef[int, OracleObjRef]
    # tracks incarnated objects for auto-disposal 
type
  Lob* = object
    ## TODO: implement
    lobtype : ParamType
    chunkSize : uint32
    lobref : ptr dpiLob

  DpiLobType* = enum CLOB = DpiOracleType.OTCLOB,
                     NCLOB = DpiOracleType.OTNCLOB,
                     BLOB = DpiOracleType.OTBLOB
                
include odpi_obj2string
# contains some utility templates for object to string conversion (debug)
include odpi_to_nimtype
# some helper template for dealing with byte sequences/date types
include nimtype_to_odpi
# helper templates for copying nim types into ODPI-C domain                  

template newStringColTypeParam*(strlen: int): ColumnType =
  ## helper to construct a string ColumnType with specified len
  (DpiNativeCType.BYTES, DpiOracleType.OTVARCHAR, strlen, false, 0.int8,
   "",0.int16,0.uint8
  )

template newRawColTypeParam*(bytelen: int): ColumnType =
  ## helper to construct a string ColumnType with specified len
  (DpiNativeCType.BYTES, DpiOracleType.OTRAW,bytelen,true, 0.int8,
   "",0.int16,0.uint8
  )

template `[]`*(rs: ResultSet, colidx: int): ParamTypeRef =
  ## selects the column of the resultSet.
  rs.rsOutputCols[colidx]

template `[]`*(row: DpiRow, colname: string): ptr dpiData =
  ## access of the iterators dataCell by column name.
  ## if the column name is not present an nil ptr is returned
  var cellptr : ptr dpiData = cast[ptr dpiData](0)
  for i in row.rawRow.low .. row.rawRow.high:
    if cmp(colname, row.rset.rsOutputCols[i].columnType.name) == 0:
      # specified row found
      cellptr = row.rawRow[i]
      break;
  cellptr

template `[]`*(row: DpiRow, index : int ): ptr dpiData =
  ## access of the iterators dataCell by index (starts with 0)
  row.rawRow[index]  

template toObject*( val : ptr dpiData) : ptr dpiData =
  ## FIXME: eval if needed
  val.value.asObject

template `[]`(data: ptr dpiData, idx: int): ptr dpiData =
  ## direct access of a column's cell within the columnbuffer by index.
  ## internal - used by DpiRow for calculating the ptr. 
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
    if not rs.boundParams[i].isNil and
      rs.boundParams[i].bindPosition.kind == byPosition and
      rs.boundParams[i].bindPosition.paramVal.int == bindidx.int:
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
    if not rs.boundParams[i].isNil and
      rs.boundParams[i].bindPosition.kind == byName and
      cmp(paramName, rs.boundParams[i].bindPosition.paramName) == 0:
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
       dpiContext_createWithParams(DPI_MAJOR_VERSION, DPI_MINOR_VERSION, nil, addr(
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
  #FIXME: check wallet operation
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
  ## creates a new subscription (notification) on database events
  # TODO: test missing              
  if DpiResult(dpiConn_subscribe(conn.connection, 
                     params,outSubscr)).isFailure:
    raise newException(IOError, "subscribe: " &
      getErrstr(conn.context.oracleContext))
    {.effects.}
                
proc unsubscribe(conn : var OracleConnection, subscription : ptr dpiSubscr) =
  ## unsubscribe the database event subscription
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
  outPs.scrollable = false # always false due to missing implementation
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


template setClientLibPrefetchRows*(ps : var PreparedStatement, numRows : uint32) =
  ## overrides the clients lib DPI_DEFAULT_PREFETCH_ROWS default. setting it to 0
  ## will completely disable prefetching
  if DpiResult(dpiStmt_setPrefetchRows(ps.pstmt,numRows)).isFailure:
    raise newException(IOError, "setClientLibPrefetchRows: " &
    " error while setting number of prefetched rows : " & getErrstr(
        ps.relatedConn.context.oracleContext))
    {.effects.}
  
template getClientLibPrefetchRows*(ps : var PreparedStatement) : uint32 =
  ## gets the number of rows the client lib is prefetching. 
  var numrows : uint32 = 0
  if DpiResult(dpiStmt_getPrefetchRows(ps.pstmt,numrows.addr)).isFailure:
    raise newException(IOError, "getClientLibPrefetchRows: " &
    " error while getting number of prefetched rows : " & getErrstr(
        ps.relatedConn.context.oracleContext))
    {.effects.}
  numrows

template releaseParameter(ps : var PreparedStatement, param : ParamTypeRef) =
  ## frees the internal dpiVar resources
  if DpiResult(dpiVar_release(param.paramVar)).isFailure:
    raise newException(IOError, " releaseParameter: " &
    "error while calling dpiVar_release : " & getErrstr(
        ps.relatedConn.context.oracleContext))
    {.effects.}

template initAttributes(objType : OracleObjTypeRef ) = 
  ## introspects and initializes the object types attributes if present
  objType.columnTypeList = newSeq[ColumnType](objType.objectTypeInfo.numAttributes)
  objType.namedColumnTypes = newTable[string,OracleObjTypeRef]()

  # setup attribute list
  # todo: check if attributes present
  if objType.objectTypeInfo.numAttributes > 0.uint16:
    objType.attributes = 
      newSeq[ptr dpiObjectAttr](objType.objectTypeInfo.numAttributes)

    if DpiResult(dpiObjectType_getAttributes(objType.baseHdl,
                                             objType.objectTypeInfo.numAttributes,
                                             objType.attributes[0].addr
      )).isFailure:
      raise newException(IOError, "lookupAttributes: " &
                              getErrstr(objType.relatedConn.context.oracleContext))
      {.effects.}


    var attrInfo : dpiObjectAttrInfo

    for i in objType.columnTypeList.low .. objType.columnTypeList.high:
      discard dpiObjectAttr_getInfo(objType.attributes[i],attrInfo.addr)
      var attrName : string =  newString(attrInfo.nameLength)
      copyMem(addr(attrName[0]),attrInfo.name,attrInfo.nameLength) 
   
      objType.columnTypeList[i] = (DpiNativeCType(attrInfo.typeInfo.defaultNativeTypeNum),
                                             DpiOracleType(attrInfo.typeInfo.oracleTypeNum),
                                             attrInfo.typeInfo.clientSizeInBytes.int,
                                             true,
                                             attrInfo.typeInfo.scale,
                                             attrName,
                                             attrInfo.typeInfo.precision,
                                             attrInfo.typeInfo.fsPrecision
                                             )


proc initObjectTypeHdl(objType : OracleObjTypeRef,  hdl : ptr dpiObjectType ) =
  ## init the OracleObjTypeRef out of it's ODPI-C object-type.
  ## if the type is a collection it's childObjectType is also introspected
  # FIXME: at the moment nested Types need rework
  objType.baseHdl = hdl  

  if DpiResult(dpiObjectType_getInfo(objType.baseHdl,
                                     objType.objectTypeInfo.addr)).isFailure:
    raise newException(IOError, "lookupInfoType: " &
                              getErrstr(objType.relatedConn.context.oracleContext))
    {.effects.}

  if objType.objectTypeInfo.isCollection == 1:
    objType.isCollection = true
    objType.elementDataTypeInfo = objType.objectTypeInfo.elementTypeInfo.addr
    discard dpiObjectType_getInfo(objType.elementDataTypeInfo.objectType,
                                  objType.elementObjectTypeInfo)
    # introspect element type of the container 

    var objinf : dpiObjectTypeInfo
    discard dpiObjectType_getInfo(objType.elementDataTypeInfo.objectType,objinf.addr)
    var childobjname = fetchObjectTypeName(objinf)
    echo "collection type detected. child-type: " & childobjname 
    objType.childObjectType = OracleObjTypeRef()
    # objType.childObjectType.isCollection = false
    objType.childObjectType.relatedConn = objType.relatedConn
    objType.childObjectType.initObjectTypeHdl(objType.elementDataTypeInfo.objectType)
    # objType.childObjectType = lookupObjectType(objType.relatedConn,childobjname) 
    # auto introspect the child type. at the moment nested collections not supported 
  
  else: 
    objType.isCollection = false
    objType.initAttributes
    # objectType is no collection - init attributes
  
  objType.tmpAttrData = cast[ptr dpiData](alloc0(sizeof(dpiData)))
  # alloc mem for raw fetching attribute values

  #FIXME: rework. at the moment no Object-Type-Attributes possible



template newVar(ps: var PreparedStatement, param: ParamTypeRef) =
  # internal template to create a new in/out/inout binding variable
  # according to the ParamTypeRef's settings
  var isArray: uint32 = 0
  if param.isPlSqlArray:
    isArray = 1
    # quirky

  if DpiResult(dpiConn_newVar(
         ps.relatedConn.connection,
         cast[dpiOracleTypeNum](param.columnType.dbType.ord),
         cast[dpiNativeTypeNum](param.columnType.nativeType.ord),
         param.rowBufferSize.uint32, #maxArraySize
    param.columnType.colsize.uint32, #size
    param.columnType.sizeIsBytes.cint,
    isArray.cint,
    param.objectTypeHandle,
    param.paramVar.addr, # out
    param.buffer.addr    # out
  )).isFailure:
    raise newException(IOError, "bindParameter: " &
          "error while calling dpiConn_newVar : " & getErrstr(
              ps.relatedConn.context.oracleContext))
    {.effects.}


proc newParamTypeRef(ps: var PreparedStatement,
                      bindInfo: BindInfo,
                      coltype: ColumnType,
                      isPlSqlArray: bool,
                      boundRows: int, 
                      objHdl : ptr dpiObjectType = nil): ParamTypeRef =
  result = ParamTypeRef(bindPosition: bindInfo,
                         columnType: coltype,
                         paramVar: nil,
                         buffer: nil,
                         rowBufferSize: boundRows,
                         isPlSqlArray: isPlSqlArray,
                         isFetched: false,
                         objectTypeHandle : objHdl)

proc addBindParameter*(ps: var PreparedStatement,
                         coltype: ColumnType,
                         paramName: string) : ParamTypeRef =
  ## constructs a non-array bindparameter by parameterName.
  ## throws IOException in case of error.
  ## see https://oracle.github.io/odpi/doc/user_guide/data_types.html
  ## for supported type combinations of ColumnType.
  ## the parametername must be referenced within the
  ## query with colon. example :<paramName>
  ## after adding the parameter, the value can be set with the typed setters
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
  ## query with colon. example :<paramIndex>.
  ## the parameter value can be set with the typed setters on the ParamType.
  ## the type of the parameter is implicit in,out or in/out.
  ## this depends on the underlying query
  result = newParamTypeRef(ps, BindInfo(kind: BindInfoType.byPosition,
                                paramVal: idx), coltype,false,1.int)
  newVar(ps, result)
  ps.boundParams.add(result)
                           
proc addArrayBindParameter*(ps: var PreparedStatement,
                       coltype: ColumnType,
                       paramName: string,
                       rowCount : int, 
                       isPlSqlArray : bool = false) : ParamTypeRef =
  ## constructs an array bindparameter by parameterName.
  ## array parameters are used for bulk-insert or plsql-array-handling
  ## throws IOException in case of error. isPlSqlArray is true only for
  ## index by tables.
  ## see https://oracle.github.io/odpi/doc/user_guide/data_types.html
  ## for supported type combinations of ColumnType.
  ## the parametername must be referenced within the
  ## query with a colon. example :<paramName>
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
  ## throws IOException in case of error.  isPlSqlArray is true only for
  ## index by tables.
  ## see https://oracle.github.io/odpi/doc/user_guide/data_types.html
  ## for supported type combinations of ColumnType.
  ## the parameterindex must be referenced within the
  ## query with a colon. example :<paramIndex>.
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


proc addObjectBindParameter*(ps: var PreparedStatement,
                             idx: BindIdx,
                             objType : OracleObjTypeRef,
                             rowCount : int , 
                             isPlSqlArray : bool = false ): ParamTypeRef =
  ## constructs a object bindparameter by parameter index.
  ## this bindparameter is an array parameter type.  isPlSqlArray is true only for
  ## index by tables.
  ## array parameters are used for bulk-insert or plsql-array-handling.
  ## throws IOException in case of error.
  ## the parameterindex must be referenced within the
  ## query with a colon. example :<paramIndex>.
  ## the parameter value can be set with the typed setters on the ParamType.
  ## the type of the parameter is implicit in,out or in/out.
  ## this depends on the underlying query
  if ps.bufferedRows < rowCount:
    raise newException(IOError, "addObjectBindParameter: " &
      "given rowCount of " & $rowCount & 
      " exceeds the preparedStatements maxBufferedRows" )
    {.effects.}

  result = newParamTypeRef(ps, 
                    BindInfo(kind: BindInfoType.byPosition,
                             paramVal: idx),
             (DpiNativeCType.OBJECT, DpiOracleType.OTOBJECT,0, 
               false, 0.int8, "",0.int16,0.uint8),
             isPlSqlArray,rowcount,objType.baseHdl)
  newVar(ps, result)
  ps.boundParams.add(result)

proc addObjectBindParameter*(ps: var PreparedStatement,
                             paramName: string,
                             objType :  OracleObjTypeRef,
                             rowCount : int, 
                             isPlSqlArray : bool = false) : ParamTypeRef =
  ## constructs a object bindparameter by parameter name (paramName)
  ## this bindparameter is an array parameter type.  isPlSqlArray is true only for
  ## index by tables.
  ## array parameters are used for bulk-insert or plsql-array-handling.
  ## throws IOException in case of error.
  ## the parameterindex must be referenced within the
  ## query with a colon. example :<paramIndex>.
  ## the parameter value can be set with the typed setters on the ParamType.
  ## the type of the parameter is implicit in,out or in/out.
  ## this depends on the underlying query
  if ps.bufferedRows < rowCount:
    raise newException(IOError, "addObjectBindParameter: " &
      "given rowCount of " & $rowCount & 
      " exceeds the preparedStatements maxBufferedRows" )
    {.effects.}

  result = newParamTypeRef(ps, 
                        BindInfo(kind: BindInfoType.byName,paramName: paramName),
                        (DpiNativeCType.OBJECT, DpiOracleType.OTOBJECT,0, 
                         false, 0.int8,"",0.int16,0.uint8),
                         isPlSqlArray,rowcount,objType.baseHdl)
  newVar(ps, result)
  ps.boundParams.add(result)


proc releaseOracleObjType( objType :  OracleObjTypeRef, isDerived : bool ) = 
  ## releases the object type obtained by lookupObjectType. 
  dealloc(objType.tmpAttrData)

  if objType.isCollection:
    objType.childObjectType.releaseOracleObjType(true)

  for i in objType.attributes.low .. objType.attributes.high:
    if DpiResult(dpiObjectAttr_release(objType.attributes[i])).isFailure:
      raise newException(IOError, "releaseOracleObjType: " &
                            getErrstr(objType.relatedConn.context.oracleContext))
      {.effects.}

  # release base handle
  if not isDerived:
    # only release not derived handles. if derived, ODPI-C will handle it
    if DpiResult(dpiObjectType_release(objType.baseHdl)).isFailure:
      raise newException(IOError, "releaseOracleObjType: " &
                              getErrstr(objType.relatedConn.context.oracleContext))
      {.effects.}

proc releaseOracleObjType*( objType :  OracleObjTypeRef) = 
  objType.releaseOracleObjType(false)

template destroy(rsVar : ParamTypeRef , prepStmt : var PreparedStatement) =
  
  # release objectParamType handles if present
  if not rsVar.rObjectTypeRef.isNil:
    rsVar.rObjectTypeRef.releaseOracleObjType(true)
  ## internal release of the paramtype refs
  ## odpic handles
  if rsVar.rAttributeHdl.len > 0:
    # frees Attribute handles
    for i in rsVar.rAttributeHdl.low .. rsVar.rAttributeHdl.high:
      discard dpiObjectAttr_release(rsVar.rAttributeHdl[i])

  if DpiResult(dpiVar_release(rsVar.paramVar)).isFailure:
    raise newException(IOError, "destroy: " &
        getErrstr(prepStmt.relatedConn.context.oracleContext))
    {.effects.}


proc destroy*(prepStmt: var PreparedStatement) =
  ## frees the preparedStatements internal resources.
  ## this should be called if
  ## the prepared statement is no longer in use.
  ## additional resources of a present resultSet
  ## are also freed. a preparedStatement with refCursor can not
  ## be reused
  # TODO: evaluate why
  for i in prepStmt.boundParams.low .. prepStmt.boundParams.high:
    prepStmt.boundParams[i].destroy(prepStmt)
    
  for i in prepStmt.rsOutputCols.low .. prepStmt.rsOutputCols.high:
    prepStmt.rsOutputCols[i].destroy(prepStmt)
      
  prepStmt.boundParams.setLen(0)
  prepStmt.rsOutputCols.setLen(0)

  if DpiResult(dpiStmt_release(prepStmt.pStmt)).isFailure:
    raise newException(IOError, "destroy: " &
      getErrstr(prepStmt.relatedConn.context.oracleContext))
    {.effects.}

                              
proc executeAndInitResultSet(prepStmt: var PreparedStatement,
                         dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord,
                         isRefCursor: bool = false ) =
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

  if prepStmt.rsOutputCols.len <= 0 and prepStmt.columnCount.int > 0:
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
                          name : colname,
                          precision : qinfo.typeinfo.precision,
                          fsPrecision : qinfo.typeinfo.fsPrecision
                          ),
                          objectTypeHandle : qinfo.typeinfo.objectType,
                          paramVar: nil,
                          buffer: nil,
                          rowBufferSize: prepStmt.bufferedRows)
                          # each out-resultset param owns the rowbuffersize
                          # of the prepared statement
      # TODO: if the objectType is not nil, query the number of attributes
      # dpiObjType->getInfo->dpiObjectTypeInfo ->elementTypeInfo->dpiDataTypeInfo->dpiObjType
      # and the object-type
      if not prepStmt.rsOutputCols[i-1].objectTypeHandle.isNil:
        var rcolobjtype = OracleObjTypeRef()
        # special case: baseObjectHandle derived out of resultset and should not be freed afterwards
        rcolobjtype.initObjectTypeHdl(prepStmt.rsOutputCols[i-1].objectTypeHandle)
        # init object type and in case of collection the childtype
        prepStmt.rsOutputCols[i-1].rObjectTypeRef = rcolobjtype
      else:
        prepStmt.rsOutputCols[i-1].rAttributeHdl = @[]

      newVar(prepStmt,prepStmt.rsOutputCols[i-1])
      # FIXME: vars not needed for fetching object types
      if DpiResult(dpiStmt_define(prepStmt.pStmt,
                                  (i).uint32,
                                  prepStmt.rsOutputCols[i-1].paramVar)
                                  ).isFailure:
        raise newException(IOError, "addOutColumn: " & $prepStmt.rsOutputCols[i-1] &
          getErrstr(prepStmt.relatedConn.context.oracleContext))
        {.effects.}
    
proc openRefCursor(ps : var PreparedStatement, 
                       p : var ParamTypeRef,
                       outRefCursor : var ResultSet,
                       bufferedRows : int,
                       dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord) =
  if p.isFetched:
    # quirky
    raise newException(IOError, "openRefCursor: " &
       """ reexecute of the preparedStatement with refCursor not supported """)
    {.effects.}
                    
  if p.columnType.nativeType == DpiNativeCType.STMT and
    p.columnType.dbType == DpiOracleType.OTSTMT:
    p.isFetched = true
    outRefCursor.pstmt = p[0].value.asStmt
    outRefCursor.relatedConn = ps.relatedConn
    outRefCursor.bufferedRows = bufferedRows
  
    executeAndInitResultSet(outRefCursor,dpiMode,true)
  
  else:
    raise newException(IOError, "openRefCursor: " &
      """ bound parameter has not the required
          DpiNativeCType.STMT/DpiOracleType.OTSTMT 
          combination """)
    {.effects.}
                    

template openRefCursor*(ps: var PreparedStatement, idx : BindIdx,
                    outRefCursor: var ResultSet,
                    bufferedRows: int,
                    dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord) =
  ## opens the refcursor on the specified bind parameter.
  ## executeStatement must be called before open it.
  ## throws IOError in case of an error
  var param : ParamTypeRef = ps[idx.BindIdx]
  openRefCursor(ps,param,outRefCursor,bufferedRows,dpiMode)

template openRefCursor*(ps: var PreparedStatement, 
                      paramName : string,
                      outRefCursor: var ResultSet,
                      bufferedRows: int,
                      dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord) =
  ## opens the refcursor on the specified bind parameter.
  ## executeStatement must be called before open it.
  ## throws IOError in case of an error
  var param = ps[paramName]
  openRefCursor(ps,param,outRefCursor,bufferedRows,dpiMode)

template resetParamRows(ps : var PreparedStatement) =
  ## resets the parameter rows to the spawned maxrow 
  ## window size of the prepared statement
  for i in ps.boundParams.low .. ps.boundParams.high:
    ps.boundParams[i].rowBufferSize = ps.bufferedRows


template updateBindParams(prepStmt: var PreparedStatement) =
  ## reset the params for reexecution of the prepared statement
  ## (rowBufferSize and bindPosition)
  for i in prepStmt.boundParams.low .. prepStmt.boundParams.high:
    let bp = prepStmt.boundParams[i]
  
    if bp.rowBufferSize > 1:
      # set the num of elements according to the rowBufferSize
      if DpiResult(dpiVar_setNumElementsInArray(bp.paramVar,
                                           bp.rowBufferSize.uint32)).isFailure:
        raise newException(IOError, "updateBindParams: " & $bp  & " " &
                            getErrstr(prepStmt.relatedConn.context.oracleContext))
        {.effects.}
                          
    if bp.bindPosition.kind == BindInfoType.byPosition:
      if DpiResult(dpiStmt_bindByPos(prepStmt.pStmt,
                                     bp.bindPosition.paramVal.uint32,
                                     bp.paramVar
        )
      ).isFailure:
        raise newException(IOError, "updateBindParams: " & $bp & " " &
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
  ## executes the PreparedStatement.
  ## the results can be fetched
  ## on a col by col base. once executed the bound columns can be reused
  ##
  ## multiple dpiModeExec values can be "or"ed together.
  ## raises IOError in case of a backend-error

  # probe if binds present
  if prepStmt.boundParams.len > 0:
    updateBindParams(prepStmt)

  prepStmt.executeAndInitResultSet(dpiMode,false)
  outRs = cast[ResultSet](prepStmt)

template executeBulkUpdate(prepStmt: var PreparedStatement,
                        numRows: int,
                        dpiMode: uint32 = DpiModeExec.DEFAULTMODE.ord) =
  ## executes the statement without returning any rows.
  ## suitable for bulk insert/update
  if prepStmt.boundParams.len > 0:
    updateBindParams(prepStmt)

  if DpiResult(dpiStmt_executeMany(prepStmt.pStmt,
                                  dpimode,
                                  numRows.uint32)).isFailure:
    raise newException(IOError, "executeMany: " &
           getErrstr(prepStmt.relatedConn.context.oracleContext))
    {.effects.}

template fetchNextRows*(rs: var ResultSet) =
  ## fetches next rows (if present) into the internal ODPI-C buffer.
  ## if DpiResult.FAILURE is returned the internal error could be retrieved
  ## by calling getErrstr on the OracleContext.
  ##
  ## After fetching, the buffer-window can be accessed by using the
  ## "[<colidx>][<rowidx>]" operator on the resultSet for native values.
  ## For typed objects please use [<colidx>].setObject or [<colidx>].getObject.
  ## No bounds check is performed.
  ## the colidx should not exceed the maximum column-count and the
  ## rowidx should not exceed the given fetchArraySize
  ##
  ## remark: no data-copy is performed.
  ## blobs and strings (pointer types) should be copied into the application
  ## domain before calling fetchNextRows again.
  ## value types are always copied on assignment.
  ## use this template only if you need a "fine granuled" access over the ResultSet -
  ## for all other cases use the iterator resultSetRowIterator instead.
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

iterator objectAttributeTypeIterator*(objType : OracleObjTypeRef) : tuple[idx : int, 
                                                                ct : ColumnType, 
                                                                hdl : ptr dpiObjectAttr] =
  ## iterates over the non-collection objects attributes. raises IOError if the
  ## named type is a collection
  if objType.isCollection:
    raise newException(IOError,"objectType is a collection. only non-collection types are iterable")                                                                 
  for i in countup(objType.columnTypeList.low,objType.columnTypeList.high):
    yield (i,objType.columnTypeList[i],objType.attributes[i])


iterator resultColumnTypeIterator*(rs : var ResultSet) : tuple[idx : int, ct: ColumnType] = 
  ## iterates over the resultSets columnTypes if present
  #FIXME: eval if practical
  for i in countup(rs.rsOutputCols.low,rs.rsOutputCols.high):
    yield (i,rs[i].columnType)

iterator resultParamTypeIterator*(rs : var ResultSet) : tuple[idx : int, pt : ParamTypeRef] =
  ## iterates over the resultsets parametertypes if present
  for i in countup(rs.rsOutputCols.low,rs.rsOutputCols.high):
    yield (i,rs[i])
 
iterator resultSetRowIterator*(rs: var ResultSet): DpiRow =
  ## iterates over the resultset row by row. no data copy is performed
  ## and ptr type values should be copied into the application
  ## domain before the next window is requested (blob/strings i.e.)
  ## do not use this iterator in conjunction with fetchNextRows because
  ## it's already used internally.
  ## in an error case an IOException is thrown with the error message retrieved
  ## out of the OracleContext.
  var p: DpiRow = DpiRow(rawRow : newSeq[ptr dpiData](rs.rsOutputCols.len), 
                         rSet : rs.addr)
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
  ## used to encapsulate the operation with a transaction.
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


template withPreparedStatement*(pstmt: var PreparedStatement, body: untyped) {.dirty.} =
  ## releases the preparedStatement after leaving
  ## the block.
  # FIXME: prevent nesting
  block:
    try:
      body
    finally:
      pstmt.destroy

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

proc introspectObjectType( base: OracleObjTypeRef , attr : ptr dpiObjectAttr ) : OracleObjTypeRef =
  ## introspects the attribute - raises exception if the attribute is not type: OBJECT
  ## or the object's column was already introspected
  discard
  

proc lookupObjectType*(conn : var OracleConnection,
                       typeName : string) : OracleObjTypeRef = 
  ## database-object-type lookup - needed for variable-object-binding.
  ## the returned OracleObjTypeRef is always bound to a specific connection.
  ## the typeName can be prefixed with the schemaname the object resides.
  ## if the OracleObjTypeRef is no longer used, the internal resources must be freed
  ## with "releaseOracleObjType" or utilize the helper template "withOracleObjType" 
  let tname : cstring = $typeName
  result = OracleObjTypeRef()
  result.relatedConn = conn
  var objHdl : ptr dpiObjectType
  echo "lookupObjectType: " & typeName
  if DpiResult(dpiConn_getObjectType(conn.connection,
                                     tname,
                                     tname.len.uint32,
                                     objHdl.addr)).isFailure:
    raise newException(IOError, "lookupObjectType: " &
      getErrstr(conn.context.oracleContext))
    {.effects.}
  result.initObjectTypeHdl(objHdl)
  return result                              
 

template isCollection*( obj : OracleObjRef ) : bool =
  ## checks if the element is a collection. true or false
  ## is returned and no exception is thrown
  obj.objType.isCollection
    
    
template setupObjBufferedColumn( obj : OracleObjRef ) = 
  ## internal template to initialize 
  ## the objects column buffer.
  ## the objects objType must be already initialized.
  ## all attributes are evaluated and extra memory is allocated
  ## in case of string and byte-types
  var buffbase : int 
  var attrlen : int = 1
  let dpiSize = sizeof(dpiData)
 
  if obj.objType.attributes.len > 0:
    attrlen = attrlen + obj.objType.attributes.len
    obj.bufferedColumn = newSeq[ptr dpiData](obj.objType.attributes.len)
    # alloc one chunk to hold all dpiData structs
    # allocate one extra chunk for the dataHelper ptr
    buffbase = cast[int](alloc0( attrlen * dpiSize ))
    # alloc0 is used because a connection should not shared between threads
    var buffbasetmp = buffbase + dpiSize
    # jump over first chunk

    for i in obj.bufferedColumn.low .. obj.bufferedColumn.high:
      obj.bufferedColumn[i] = cast[ptr dpiData](buffbasetmp)
      buffbasetmp = buffbasetmp + dpiSize
  else:
    buffbase = cast[int](alloc0( attrlen * dpiSize ))
  
  obj.dataHelper = cast[ptr dpiData](buffbase)
  
  var totalbytes = 0

  var colmap = newTable[int,ColumnType]()

  for i,column in obj.objType.columnTypeList:
    if column.nativeType == DpiNativeCType.BYTES:
      if not column.sizeIsBytes:
        raise newException(IOError,"client_size_types in character not implemented!")
      totalbytes += column.colsize 
      colmap[i] = column
  # eval all column and detect DpiNativeCType.BYTES ones
  # allocate one block, compute pointers and init dpiData section    
  obj.bufferedBytesTypeBase = cast[ptr byte](alloc0( totalbytes + 1 ))
  
  var buffer : ptr dpiData
  var segptr : int = cast[int](obj.bufferedBytesTypeBase)

  for colnum,coltype in colmap:
    # pointer computation and init each dpiData segment
    buffer = obj.bufferedColumn[colnum]
    buffer.value.asBytes.length = coltype.colSize.uint32
    buffer.value.asBytes.ptr = cast[cstring](segptr) 
    segptr += coltype.colSize

proc newOracleObject*( objType :  OracleObjTypeRef ) : OracleObjRef = 
  ## creates a new oracle object with the specified OracleObjTypeRef which can be used
  ## for binding or reading/fetching from the database.
  ## at the moment subobjects or mutual recursive types are not supported.
  ## ODPI-C and internal resources are hold till releaseOracleObject is called.
  ## variable length references must stay valid till the object sent to the database.
  ## for collection types use: newOracleCollection.
  ## if the native type is not of DpiNativeCType.OBJECT or an ODPI-C error happens 
  ## an IOError is thrown.
 
  if objType.isCollection:
    raise newException(IOError, "newOracleObject: " &
       "objectType is a collection. use newOracleCollection instead. type was: " & $objType )
    {.effects.}
  result = OracleObjRef()  
  if DpiResult(dpiObjectType_createObject(objType.baseHdl,result.objHdl.addr)).isFailure:
     raise newException(IOError, "newOracleObject: " &
       getErrstr(objType.relatedConn.context.oracleContext))
     {.effects.}
  result.objType = objType
  
  # setup buffered columns
  result.setupObjBufferedColumn

template newOracleObjectWrapper(coll : OracleCollectionRef, handle : ptr dpiObject ) : OracleObjRef =
  ## internal proc to construct the object wrapper out of a existing collection
  ## the obtained object is bound to the specified collection-type
  result = OracleObjRef()
  result.objType = coll.objType.childObjectType
  result.objHdl = handle 
  result.setupObjBufferedColumn 
  result


template initOracleCollection(collType: OracleObjTypeRef, collection: OracleCollectionRef) = 
  ## initializes a OracleCollection with the params out of the associated OracleObjType
  collection.objType =  collType
  collection.setupObjBufferedColumn
  collection.elementHelper = cast[ptr dpiData](alloc0( sizeof(dpiData) ))
  collection.incarnatedChilds = newTable[int, OracleObjRef]()


proc newOracleCollection*(collectionType : OracleObjTypeRef ) : OracleCollectionRef =
  ## create a new oracle collection object out of the OracleObjTypeRef, which can be used
  ## for binding(todo:eval) or reading/fetching from the database.
  ## ODPI-C and internal resources are hold till releaseOracleCollection is called
  ## (see withCollection helper template).
  ## variable length references must stay valid till the object sent to the database.
  ## for collection types use: newOracleCollection
  if not collectionType.isCollection:
    raise newException(IOError, "newOracleCollection: " &
       "objectType is not a collection-type and was: " & $collectionType )
    {.effects.}   
  result = OracleCollectionRef()

  collectionType.initOracleCollection(result)
  
  if DpiResult(dpiObjectType_createObject(collectionType.baseHdl,result.objHdl.addr)).isFailure:
    raise newException(IOError, "newOracleObject: " &
        getErrstr(collectionType.relatedConn.context.oracleContext))
    {.effects.}


proc releaseOracleObject*( obj : OracleObjRef ) = 
  ## releases the objects internal references and deallocs buffermem.
  dealloc(obj.dataHelper)
  dealloc(obj.bufferedBytesTypeBase)
  # fetch chunkbase
  
  if DpiResult(dpiObject_release(obj.objHdl)).isFailure:
    raise newException(IOError, "releaseOracleObject: " &
      getErrstr(obj.objType.relatedConn.context.oracleContext))
    {.effects.}

proc releaseOracleCollection*(obj : OracleCollectionRef ) =
  ## releases the objects internal references and deallocs buffermem.
  ## bound objects created by the frontend must be released separately
  ## before calling this proc
  dealloc(obj.elementHelper)

  if obj.incarnatedChilds.len > 0:
    for v in obj.incarnatedChilds.mvalues:
      releaseOracleObject(v)

  obj.incarnatedChilds.clear

template lookupObjAttrIndexByName( objType : OracleObjTypeRef, attrName : string ) : int =
  ## used by the attributeValue getter/setter to obtain the index by name.
  ## the attrName must be always UPPERCASE.
  var ctypeidx = -1
  for i in objType.columnTypeList.low .. objType.columnTypeList.high:
    if cmp(attrName, objType.columnTypeList[i].name) == 0:
      ctypeidx = i
      break;
      
  if ctypeidx == -1:
    raise newException(IOError, "lookupObjAttrIndexByName: " &
          " attrName " & attrName & " not found!")
    {.effects.}
  ctypeidx

template lookupObjAttrIndexByName( obj : OracleObjRef, attrName : string ) : int =
  lookupObjAttrIndexByName(obj.objType,attrName)

template lookupRowIndexByName( ps : ptr PreparedStatement, attrName : string) : int = 
  var rowidx = -1
  
  for i in ps.rsOutputCols.low .. ps.rsOutputCols.high:
    if cmp(attrName, ps.rsOutputCols[i].columnType.name) == 0:
      rowidx = i
      break;
      
  if rowidx == -1:
    raise newException(IOError, "lookupRowIndexByName: " &
          " attrName " & attrName & " not found!")
    {.effects.}
  rowidx

proc getAttributeValue( obj : OracleObjRef, idx : int ) : ptr dpiData = 
  ## internal getter for fetching the value of a type(dbObject) 
  ## out of the odpic-domain
  let ctype = obj.objType.columnTypeList[idx]
  let attr = obj.objType.attributes[idx]
  #FIXME: implement: If the native type is DPI_NATIVE_TYPE_BYTES and the Oracle type of the attribute
  # is DPI_ORACLE_TYPE_NUMBER, a buffer must be supplied in the value.asBytes.ptr attribute 
  # and the maximum length of that buffer must be supplied in the value.asBytes.length attribute 
  # before calling this function. 
  # if the returned handle is an object, it must be freed with dpiObject_release
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

template getCollection( row : DpiRow, colIdx : int) : OracleCollectionRef =
  ## experimental getter for resultSet collection handling
  ## the object reference returned must be freed (see template withOracleCollection)
  var result = OracleCollectionRef()
  row.rset.rsOutputCols[colIdx].rObjectTypeRef.initOracleCollection(result)
  result.objHdl = row[colIdx].value.asObject
  result 

template getColumnIndexByName(rset : ptr ResultSet, colname : string) : int =
  rset.lookupRowIndexByName

template getCollection( row : DpiRow, colName : string ) : OracleCollectionRef =
  ## experimental getter for resultSet collection handling
  ## the object reference returned must be freed
  getCollection(row,row.rset.lookupRowIndexByName(colname))


proc setAttributeValue( obj : OracleObjRef, idx: int ) = 
  ## internal setter for propagating the value of 
  ## a type(dbObject) into odpi-c domain
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


  
proc copyOracleObj*( obj : OracleObjRef ) : OracleObjRef =
  ## copies an object and returns a new independent new one
  ## which must be released if no longer needed - it it's added to a
  ## collection this is done automatically 
  result =  OracleObjRef()
  result.objType = obj.objType

  if DpiResult(dpiObject_copy(obj.objHdl,result.objHdl.addr)).isFailure:
    raise newException(IOError, "copyOracleObj: " &
      getErrstr(obj.objType.relatedConn.context.oracleContext))
    {.effects.}    
 
  result.setupObjBufferedColumn
 
proc copyOracleColl*( obj : OracleCollectionRef ) : OracleCollectionRef =
    ## copies an object and returns a new independent new one
    ## which must be released if no longer needed 
    result = OracleCollectionRef()
    result.objType = obj.objType

    result.objType.childObjectType = obj.objType.childObjectType
 
    if DpiResult(dpiObject_copy(obj.objHdl,result.objHdl.addr)).isFailure:
      raise newException(IOError, "copyOracleColl: " &
        getErrstr(obj.objType.relatedConn.context.oracleContext))
      {.effects.}

    result.setupObjBufferedColumn
    result.elementHelper = cast[ptr dpiData](alloc0( sizeof(dpiData) ))
    result.incarnatedChilds = newTable[int, OracleObjRef]()

template withOracleObjType*( objtype : OracleObjTypeRef, body: untyped) =
  ## releases the objectTypes resources after leaving
  ## the block. exceptions are not catched.
  try:
    body
  finally:
    objtype.releaseOracleObjType

template withOracleObject*( obj : OracleObjRef, body: untyped) =
  ## releases the objects resources after leaving
  ## the block. exceptions are not catched.
  try:
    body
  finally:
    obj.releaseOracleObject

template withOracleCollection*( obj : OracleCollectionRef, body: untyped) =
  ## releases the collections resources (and all bound objects) 
  ## after leaving the block. exceptions are not catched.
  try:
    body
  finally:
    obj.releaseOracleCollection
  

proc fetchCollectionSize*( collObj : OracleCollectionRef ) : int =
  ## fetches the size of a collection object. if the object
  ## is not a collection an IOException is thrown
  var csize : int32 
  if DpiResult(dpiObject_getSize(collObj.objHdl,csize.addr)).isFailure:
    raise newException(IOError, "fetchCollectionSize: " &
      getErrstr(collObj.objType.relatedConn.context.oracleContext))
    {.effects.}    

  result = csize.int 

proc deleteElementByIndex*( collObj: OracleCollectionRef, index : int ) = 
  ## delete an element from the collection. the element itself
  ## is returned and must be freed manually if needed. keep in mind that the
  ## collection is sparse.
  if DpiResult(dpiObject_deleteElementByIndex(collObj.objHdl,index.int32)).isFailure:
    raise newException(IOError, "deleteElementByIndex: " &
        getErrstr(collObj.objType.relatedConn.context.oracleContext))
    {.effects.}
  # check if element is already present
  if collObj.incarnatedChilds.hasKey(index):      
    var obj = collObj.incarnatedChilds[index]
    releaseOracleObject(obj)

proc isElementPresent*( collObj : OracleCollectionRef, index : int) : bool =
  ## probes if the element is present at the specified index.
  ## returns true if so; otherwise false.
  ## an IOException is thrown if the given object is not a collection
  var exists : cint = 0
  if DpiResult(dpiObject_getElementExistsByIndex(collObj.objHdl,
                                                index.int32,
                                                exists.addr)).isFailure:
    raise newException(IOError, "isElementPresent: " &
        getErrstr(collObj.objType.relatedConn.context.oracleContext))
    {.effects.}    
  if exists == 1 : true else: false


proc getFirstIndex*( collObj : OracleCollectionRef ) : tuple[index: int, isPresent : bool] =
  ## returns the first used index of a collection. isPresent indicates if 
  ## there was an index position found.
  var idx : int32 = 0
  var present : cint = 0
  if DpiResult(dpiObject_getFirstIndex(collObj.objHdl,
                                       idx.addr,
                                       present.addr)).isFailure:
    raise newException(IOError, "getFirstIndex: " &
        getErrstr(collObj.objType.relatedConn.context.oracleContext))
    {.effects.}    
  if present == 1 : result.isPresent = true else: result.isPresent = false
  result.index = idx.int
  
proc getLastIndex*( collObj : OracleCollectionRef ) : tuple[index: int, isPresent : bool] =
  ## returns the last used index of a collection. isPresent indicates if 
  ## there was an index position found. an IOException is thrown if the
  ## object is not a collection.
  var idx : int32 = 0
  var present : cint = 0
  if DpiResult(dpiObject_getLastIndex(collObj.objHdl,
                                       idx.addr,
                                       present.addr)).isFailure:
    raise newException(IOError, "getLastIndex: " &
        getErrstr(collObj.objType.relatedConn.context.oracleContext))
    {.effects.}    
  if present == 1 : result.isPresent = true else: result.isPresent = false
  result.index = idx.int

proc getNextIndex*( collObj : OracleCollectionRef, 
                    index : int ) : tuple[index: int, isPresent : bool] =
    ## returns the next used index from the given index position of a collection. 
    ## isPresent indicates if there was an index position found. 
    ## an IOException is thrown if the
    ## object is not a collection.
    var idx : int32 = 0
    var present : cint = 0
    if DpiResult(dpiObject_getNextIndex(collObj.objHdl,index.int32,
                                         idx.addr,
                                         present.addr)).isFailure:
      raise newException(IOError, "getNextIndex: " &
          getErrstr(collObj.objType.relatedConn.context.oracleContext))
      {.effects.}    
    if present == 1 : result.isPresent = true else: result.isPresent = false
    result.index = idx.int
  

proc getPreviousIndex*( collObj : OracleCollectionRef, 
                        index : int ) : tuple[index: int, isPresent : bool] =
  ## returns the previous used index from the given index position of a collection. 
  ## isPresent indicates if there was an index position found. 
  ## an IOException is thrown if the
  ## object is not a collection.
  var idx : int32 = 0
  var present : cint = 0
  if DpiResult(dpiObject_getPrevIndex(collObj.objHdl,index.int32,
                                       idx.addr,
                                       present.addr)).isFailure:
    raise newException(IOError, "getPreviousIndex: " &
        getErrstr(collObj.objType.relatedConn.context.oracleContext))
    {.effects.}    
  if present == 1 : result.isPresent = true else: result.isPresent = false
  result.index = idx.int
    
proc appendElement*( collObj : OracleCollectionRef, 
                     obj2append : OracleObjRef) = 
  ## appends the object (param: obj) to ( param : collObj) at the
  ## end of the collection. 
  ## throws an IOError if the collectionObject
  ## is not a collection or if the object to append is 
  ## already related to a collection
  ## or an internal error occurs.
  
  dpiData_setObject(obj2append.dataHelper,obj2append.objHdl)
  obj2append.dataHelper.setNotDbNull
  
  if DpiResult(dpiObject_appendElement(collObj.objHdl,
                                       DpiNativeCType.Object.ord,
                                       obj2append.dataHelper)).isFailure:
    raise newException(IOError, "appendElement: " &
      getErrstr(obj2append.objType.relatedConn.context.oracleContext))
    {.effects.}       
  var idx = getLastIndex(collObj)
  collObj.incarnatedChilds[idx.index] = obj2append
  
proc trimCollection*( collObj : OracleCollectionRef, resizeVal : int ) =
  ## Trims the given numer of elements from the end of the collection.
  ## an IOException is thrown if the object is not a collection.
  ## the elements itself must be freed manually.
  if DpiResult(dpiObject_trim(collObj.objHdl,resizeVal.uint32)).isFailure:
    raise newException(IOError, "trimCollection: " &
      getErrstr(collObj.objType.relatedConn.context.oracleContext))
    {.effects.}
  # FIXME: TODO: adjust incarnatedChilds map      

proc setElementValue2Backend(collObj : OracleCollectionRef, 
                            index : int ) =
  ## internal collection object setter with index. the collObj.elementHelper
  ## dpiData structure must already populated before calling this proc.
  ## this proc is generic and collection dependent if the object-type
  ## is another object or native type.
  ##  
  ## an IOException is thrown if the object is not a collection
  ## or an internal error occurs
  if DpiResult(dpiObject_setElementValueByIndex(collObj.objHdl,
                                           index.int32,
                              collObj.objType.elementDataTypeInfo.defaultNativeTypeNum,
                              collObj.elementHelper)).isFailure:
    raise newException(IOError, "setElementValueByIndex: " &
      getErrstr(collObj.objType.relatedConn.context.oracleContext))
    {.effects.}    

proc getElementValueFromBackend(collObj : OracleCollectionRef,
                             index : int) : ptr dpiData =
  ## internal collection object getter with index. returns the
  ## populated dpiData structure. due to the ptr handling an explicit
  ## setter is not provided. can be used both for DpiNativeCType.OBJECT
  ## or native types (the value from member dpiDataTypeInfo.defaultNativeTypeNum is used)
  ## an IOException is thrown if the object is not a collection
  ## or an internal error occurs.
  ## FIXME: implement external buffer for 
  ## DPI_NATIVE_TYPE_BYTES and the Oracle type of the attribute is DPI_ORACLE_TYPE_NUMBER
  ## 
  ## https://oracle.github.io/odpi/doc/functions/dpiObject.html
  if DpiResult(dpiObject_getElementValueByIndex(collObj.objHdl,index.int32,
               collObj.objType.elementDataTypeInfo.defaultNativeTypeNum,
                  collObj.elementHelper)).isFailure:
    raise newException(IOError, "getElementValueByIndex: " &
      getErrstr(collObj.objType.relatedConn.context.oracleContext))
    {.effects.}    
     # retrieve child-type with DpiNativeCType.Object.ord
    ## TODO: how to introspect dpiData?
    ## FIXME: dpiObject_release called?
    ## collObj.objType.elementDataTypeInfo.defaultNativeTypeNum
  return collObj.elementHelper

proc getElementValue( srcObj : ptr dpiData, srcType : OracleObjTypeRef, idx : int) : ptr dpiObject =
  # returns the value dpiObject *dpiData_getObject(dpiData *data)
  # TODO: implement
  discard

proc setCollectionElement(collObj : OracleCollectionRef, 
                            index : int, 
                            value : OracleObjRef) =
  ## sets a collection element at the specified index location.
  ## before calling, the internal helper structure must be populated.
  ## the first index location is 0 
  dpiData_setObject(collObj.elementHelper,value.objHdl)
  collObj.setElementValue2Backend(index)
  
proc getCollectionElement(collObj : OracleCollectionRef, index : int) : OracleObjRef =
  ## fetches object buffer at the specified index.
  ## if the related element type is not of type DpiNativeCType.OBJECT an IOException
  ## is thrown. the collection index starts with 0.
  ## if the object was already fetched, the internal tracked object is returned.
  ## for native typed collection elements please use the
  ## fetch/set templates.
  if not collObj.objType.
            elementDataTypeInfo.defaultNativeTypeNum == 
              DpiNativeCType.OBJECT.ord:
    raise newException(IOError, "getCollectionElement: " &
      "related native type must be OBJECT but was: " & 
       $collObj.objType.elementDataTypeInfo )
    {.effects.}

  if collObj.isElementPresent(index):
    if collObj.incarnatedChilds.hasKey(index):
      # echo "obj incarnated - read map"
      # TODO: eval why it's called that often with "[][]" access
      result = collObj.incarnatedChilds[index]
    else:
      let objptr = cast[ptr dpiObject](collObj.getElementValueFromBackend(index).
                                  value.asObject)
      result = newOracleObjectWrapper(collObj,objptr)
      collObj.incarnatedChilds[index] = result                                  
  else:
    raise newException(IOError,"getCollectionElement: no elem present at index " & $index)


proc setObject*(param : ParamTypeRef, rownum : int, value : OracleObjRef ) =
  ## sets a bind parameter with value type: OracleObjRef
  if DpiResult(dpiVar_setFromObject(param.paramVar,
                                    rownum.uint32,
                                    value.objHdl)).isFailure:
    raise newException(IOError, "setObject: " &
        getErrstr(value.objType.relatedConn.context.oracleContext))
    {.effects.}   

proc setCollection*(param : ParamTypeRef, rownum : int, value : OracleCollectionRef ) =
  ## sets a bind parameter with value type: OracleCollectionRef  
  if DpiResult(dpiVar_setFromObject(param.paramVar,
                                    rownum.uint32,
                                    value.objHdl)).isFailure:
    raise newException(IOError, "setCollection: " &
        getErrstr(value.objType.relatedConn.context.oracleContext))
    {.effects.}   


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

# TODO: varray,blob,clob and AQ support
# TODO: FIXME: remove Objects bufferedColumn quirk

include setfetchtypes
  # includes all fetch/set templates

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
 
  for i,ct in rs.resultColumnTypeIterator:
    # consume columnTypes of the resultSet
    echo "cname:" & rs.rsColumnNames[i] & " colnumidx: " & 
      $(i+1) & " " & $ct

  for row in rs.resultSetRowIterator:
    # the result iterator fetches internally further
    # rows if present 
    # example of value retrieval by columnname or index
    # the column of the row is accessed by colnum or name
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

  for row in rs.resultSetRowIterator:
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
  # implicit results example (ref cursor)
  # FIXME: test typed plsql blocks

  var pstmt2 : PreparedStatement
  # refcursor example
  newPreparedStatement(conn, refCursorQuery, pstmt2, 1)
  # this query block contains two independent refcursors
  # and the snd is parameterised.

  withPreparedStatement(pstmt2):
    discard pstmt2.addBindParameter(RefCursorColumnTypeParam,BindIdx(1))
    # to consume the refcursor a bindParameter is needed (bind by index)                                   
    discard pstmt2.addBindParameter(RefCursorColumnTypeParam,"refc2")
    # example of bind by name (alternative to bind by index)
    discard pstmt2.addBindParameter(Int64ColumnTypeParam,BindIdx(3))
    # filter: parameter for department_id                                   
    pstmt2[3.BindIdx].setInt64(some(80.int64))
    # sets the value of the bind parameter

    pstmt2.executeStatement(rs)

    echo "refCursor 1 results: "
    var refc: ResultSet

    pstmt2.openRefCursor(1.BindIdx, refc, 1, DpiModeExec.DEFAULTMODE.ord)
    # opens the refcursor. once consumed it can't be reopended (TODO: check
    # if that's a ODPI-C limitation)
    for row in refc.resultSetRowIterator:
      echo $row[0].fetchString

    echo "refCursor 2 results: filter with department_id = 80 "

    var refc2 : ResultSet
    pstmt2.openRefCursor("refc2", refc2, 10, DpiModeExec.DEFAULTMODE.ord)

    for row in refc2.resultSetRowIterator:
      echo $row[0].fetchString & " " & $row[1].fetchString


  # object-type for testing the obj-features
  # nested obj not implemented at the moment.
  var demoCreateObj : SqlQuery = osql"""
    create or replace type HR.DEMO_OBJ FORCE as object (
      NumberValue                         number(15,8),
      StringValue                         varchar2(60),
      FixedCharValue                      char(10),
      DateValue                           date,
      TimestampValue                      timestamp,
      RawValue                            raw(25) 
    );
   """
  conn.executeDDL(demoCreateObj)

  var ctableq = osql""" CREATE TABLE HR.DEMOTESTTABLE(
                        C1 VARCHAR2(20) NOT NULL 
                      , C2 NUMBER(5,0)
                      , C3 raw(20) 
                      , C4 NUMBER(5,3)
                      , C5 NUMBER(15,5)
                      , C6 TIMESTAMP
                      , C7 HR.DEMO_OBJ
                      , CONSTRAINT DEMOTESTTABLE_PK PRIMARY KEY(C1)  
    ) """ 
 
  conn.executeDDL(ctableq) 
  echo "table hr.demotesttable created"

  var demoObjType = conn.lookupObjectType("HR.DEMO_OBJ")

  var insertStmt: SqlQuery =
    osql""" insert into HR.DEMOTESTTABLE(C1,C2,C3,C4,C5,C6,C7) 
                                values (:1,:2,:3,:4,:5,:6,:7) """

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
  discard pstmt3.addObjectBindParameter(7.BindIdx,demoObjType,10)
  # if a nativeType/oracleType combination is not implemented by ODPI-C
  # you will receive an exception here

  var rset: ResultSet
  # TODO: checkout new prefetch size feature
  # https://cx-oracle.readthedocs.io/en/latest/user_guide/tuning.html#choosing-values-for-arraysize-and-prefetchrows 
  pstmt3.withPreparedStatement:
    var tseq = some(@[(0xAA).byte,0xBB.byte,0xCC.byte])
    var pks = @[some("test_äüö0"),some("test_äüö1"),some("test_äüö2"),
                some("test_äüö3"),some("test_äüö4"),some("5"),
                some("6"),some("7"),some("8"),some("9"),
                some("10"),some("11"),some("12")]
    # strings and bytearrays are pointer types and need to stay valid till the transaction is committed.
    # exception: OracleObject types (each objcolumn of string/bytearray are buffered)
   
    var objBuffer = newSeq[OracleObjRef](13)
    for i in 0..12:
      echo "new object"
      objBuffer[i] = demoObjType.newOracleObject
    
    # init obj buffer for the next example 
    conn.withTransaction: # commit after this block
      # cleanup of preparedStatement beyond this block
      var varc2 : Option[int64]

      #var obj1 = demoObjType.newOracleObject      
      #obj1.setDouble(0,some(22.float64))
      #obj1.setString(1,some("teststring"))
      
      for i,bufferRowIdx in pstmt3.bulkBindIterator(12,8):
        # i: count over 13 entries - with a buffer window of 9 elements
        # if the buffer window is filled
        # contents are flushed to the database.
        if i == 9:
          varc2 = none(int64) # simulate dbNull
        else:
          varc2 = some(i.int64)
        # unfortunately setString/setBytes have a different
        # API than the value-parameter types
        echo pks[i].get
        pstmt3[1.BindIdx][bufferRowIdx].setString(pks[i]) #pk
        pstmt3[2.BindIdx][bufferRowIdx].setInt64(varc2)
        pstmt3[3.BindIdx][bufferRowIdx].setBytes(tseq)
        pstmt3[4.BindIdx][bufferRowIdx].setFloat(some(i.float32+0.12.float32))
        pstmt3[5.BindIdx][bufferRowIdx].setDouble(some(i.float64+99.12345.float64))
        pstmt3[6.BindIdx][bufferRowIdx].setDateTime(some(getTime().local))
        objBuffer[i].setDouble("NUMBERVALUE",some(i.float64))
        # access by columnName
        objBuffer[i].setString(1,some("teststring" & $i))
        # or columnIndex
        pstmt3[7.BindIdx].setObject(bufferRowIdx,objBuffer[i])
    
    for i in objBuffer.low..objBuffer.high:
      objBuffer[i].releaseOracleObject
    objBuffer.setLen(0)

    # example: reuse of preparedStatement and insert another 8 rows
    # with a buffer window of 3 elements 
    var pks2 = @[some("test_äüö15"),some("test_äüö16"),some("test_äüö17"),some("test_äüö18"),
                 some("test_äüö19"),some("20"),some("21"),some("22")]

    conn.withTransaction:
      var seqnone = none(seq[byte])
      for i,bufferRowIdx in pstmt3.bulkBindIterator(7,2):
        pstmt3[1.BindIdx][bufferRowIdx].setString(pks2[i]) #pk
        pstmt3[2.BindIdx][bufferRowIdx].setInt64(some(i.int64))
        pstmt3[3.BindIdx][bufferRowIdx].setBytes(seqnone)   # dbNull
        pstmt3[4.BindIdx][bufferRowIdx].setFloat(none(float32))     # dbNull
        pstmt3[5.BindIdx][bufferRowIdx].setDouble(none(float64))    # dbNull
        pstmt3[6.BindIdx][bufferRowIdx].setDateTime(none(DateTime)) # dbNull
        pstmt3[7.BindIdx][bufferRowIdx].setDbNull
        # TODO: eval howto set a bound object within existing buffer to dbNull
   
  var selectStmt: SqlQuery = osql"""select c1,c2,rawtohex(c3)
                                         as c3,c4,c5,c6,c7 from hr.demotesttable"""
      # read now the committed stuff

  var pstmt4 : PreparedStatement
  var rset4 : ResultSet

  conn.newPreparedStatement(selectStmt, pstmt4, 5)
  # test with smaller window: 5 rows are buffered internally for reading

  echo "prepare reading hr.demotesttable"
  withPreparedStatement(pstmt4): 
    pstmt4.executeStatement(rset4)
    for row in rset4.resultSetRowIterator:       
      echo $row[0].fetchString & "  " & $row[1].fetchInt64 & 
            " " & $row[2].fetchString & 
          # " "  & $fetchFloat(row[3].data) &
          # TODO: eval float32 vals 
            " " & $row[4].fetchDouble & " " & $row[5].fetchDateTime
          # FIXME: fetchFloat returns wrong values / dont work as expected
    
    echo "finished reading hr.demotesttable"
  echo "prepared statement removed"
      # drop the table
  var dropStmt: SqlQuery = osql"drop table hr.demotesttable"
  conn.executeDDL(dropStmt)
    # cleanup - table drop
  echo "HR.DEMOTESTTABLE dropped"
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
    var p1 = some("teststr äüö")
    var p2 = some("p2")
    param2.setString(p1) 
    param3.setString(p2)
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


  # create collection type
  var demoCreateColl : SqlQuery = osql"""
    create or replace TYPE HR.DEMO_COLL  IS TABLE OF HR.DEMO_OBJ; """

  conn.executeDDL(demoCreateColl)  

  var demoAggr : SqlQuery = osql"""
      create or replace FUNCTION  HR.DEMO_COLAGGR 
       -- naive collection aggregation (no real world example)
         (
           PARAM1 IN HR.DEMO_COLL
          ) RETURN VARCHAR2 AS
             px1 varchar2(3000) := 'table_parameter_was_null';
          BEGIN
           if param1 is not null then
             px1 := '';
             if param1.count > 0 then
              for i in param1.first .. param1.last 
               loop
                px1 := px1 || param1(i).StringValue;
               end loop;
            else
             px1 := 'table_is_empty';
            end if;
           end if;
           dbms_output.put_line(px1);
        RETURN px1;
      END DEMO_COLAGGR;
  """
 
  # create target function
  conn.executeDDL(demoAggr)  

  # lookup type and print results
  echo "lookup demo_obj"
  var objtype = conn.lookupObjectType("HR.DEMO_OBJ")
  var obj  = objtype.newOracleObject
 
  obj.setDouble(0,some(100.float64))
  obj.setString(1,some("teststring"))
  echo $(obj[0].fetchDouble) 
  echo $(obj[1].fetchString) 
  
  # not public
  # value from buffer
  
  echo $obj.fetchDouble(0) # value from odpi-c
  # public api 

  var copyOf = obj.copyOracleObj
  copyOf.setDouble(0,some(200.float64))

  echo $copyOf.fetchDouble(0) # value from odpi-c
  echo "lookup column-type"
  
  var colltype = conn.lookupObjectType("HR.DEMO_COLL")
  echo "begin create oracle collection"
  var collection = colltype.newOracleCollection
  echo "oracleCollection created"
  # echo $colltype.elementDataTypeInfo
  var objinf : dpiObjectTypeInfo


  echo "--------------------- begin collection type tests -----------------------"
 
  withOracleCollection(collection):
    collection.appendElement(copyof)
    collection.appendElement(obj)

    echo " size of collection: " & $collection.fetchCollectionSize

    var copyOfColl = collection.copyOracleColl

    echo "before copy: childtype is: " & $collection.objType.childObjectType.isNil


    # copies the entire collection
    withOracleCollection(copyOfColl):
      echo " size of copied collection: " &  
        $copyOfColl.fetchCollectionSize
      echo "elem 0 " & $copyOfColl.isElementPresent(0)
      echo "elem 1 " & $copyOfColl.isElementPresent(1)
      echo $copyOfColl.getFirstIndex
      echo $copyOfColl.getLastIndex

      var res : ptr dpiObject 
      # begin testcode
      if not copyOfColl.objType.
            elementDataTypeInfo.defaultNativeTypeNum == 
              DpiNativeCType.OBJECT.ord:
                raise newException(IOError, "getCollectionElement: " &
                  "related native type must be OBJECT but was: " & 
                  $copyOfColl.objType.elementDataTypeInfo )
    
      if copyOfColl.isElementPresent(0):
        echo "elem 0 in collection present"
                                  
      else:
        echo "elem 0 in collection not present. set to dbNull"
        copyOfColl.elementHelper.setDbNull
        # res = cast[ptr dpiObject](copyOfColl.elementHelper)

      # end testcode
      echo "---------- end of coltype testcode ---------------"  
      # fetches the member objects attribute at index 0 of the collections
      # member object at index 1 
      copyOfColl[0].setDouble(0,some(22.float64)) # = some(22.float64)
      copyOfColl[1].setDouble(0,some(10.float64))
      echo $copyOfColl[1][0].fetchDouble
      #fetch the first attribute of a collection member at attribute position 0
      echo $copyOfColl[0][0].fetchDouble
      #fetch the first attribute of a collection member at attribute position 0
      
      # initialize string fields and call the aggregate udf
      echo "begin aggregate udf tests"
      collection[0].setString(1,some("hello nim! "))  
      collection[1].setString(1,some("from oracle "))
      copyOfColl[0].setDateTime(4,some(getTime().local))
      copyOfColl[1].setDateTime(4,some(getTime().local))
         
      # TODO: call the procedure with select statement
      # in another example
      var demoCallAggr = osql"""begin :1 := HR.DEMO_COLAGGR(:2); end; """
      var callFuncAggr : PreparedStatement
      var callFuncResultAggr : ResultSet
      
      newPreparedStatement(conn,demoCallAggr,callFuncAggr,5)
  
      withPreparedStatement(callFuncAggr):
        # call the function with direct parameter access and object as parameter
        let param1 = callFuncAggr.addBindParameter(newStringColTypeParam(500),BindIdx(1))
        let param2 = callFuncAggr.addObjectBindParameter(BindIdx(2),colltype,5)
        param2.setObject(0,copyOfColl) # todo: consolidate API
        callFuncAggr.executeStatement(callFuncResult)
        echo "result of hr.demo_colaggr: " & $param1.fetchString()
   
      # same example with invocation from sql 
      var nestedtabStmt = osql"""
                                 create table HR.NDEMO (
                                   ntestname varchar2(30)
                                   , testcol hr.demo_coll
                                   , CONSTRAINT NDEMO_PK PRIMARY KEY(ntestname) 
                                   )
                                nested table testcol store as nested_demo_coll
                              """
      conn.executeDDL(nestedtabStmt)
      echo "--------------------- nested table HR.NDEMO created -----------------------"

      var nestedtableInsert = osql""" insert into HR.NDEMO(NTESTNAME,TESTCOL) values (:1,:2) """
      
      var nInsertPstmt : PreparedStatement
      var nInsertRset : ResultSet
      newPreparedStatement(conn,nestedtableInsert,nInsertPstmt,10)

      withPreparedStatement(nInsertPstmt):
        conn.withTransaction:
          let param1 = nInsertPstmt.addArrayBindParameter(
                                    newStringColTypeParam(30),
                                    BindIdx(1),10)
          let param2 = nInsertPstmt.addObjectBindParameter(BindIdx(2),colltype,10)
          var keys = @[some("testname1"),some("testname2"),some("testname3"),
                       some("testname4"),some("testname5"),some("testname6")]          
          for i,bufferRowIdx in nInsertPstmt.bulkBindIterator(5,0):
            # commit after each row required or 
            # the objects contents are overwritten
            copyOfColl[0].setString(1,some("hello nim! round " & $i))
            copyOfColl[1].setString(1,some("from oracle "))
            copyOfColl[0].setDateTime(4,some(getTime().local))
            copyOfColl[1].setDateTime(4,some(getTime().local))
            copyOfColl[1].setBytes(5,some(@[(0xAA+i).byte,0xBB,0xCC]))
            # feed the copyOfColl collection
            # update object per round
            nInsertPstmt[1.BindIdx][bufferRowIdx].setString(keys[i])
            # access the cell via prepared statement and bindindex
            nInsertPstmt[2.BindIdx].setCollection(bufferRowIdx,copyOfColl)
            # variant2: param2.setCollection(bufferRowIdx,copyOfColl)
            # access the cell directly via the bind parameter
            
      echo "insert finished "
      var nestedtableSelect = osql" select NTESTNAME,TESTCOL from HR.NDEMO "
      var nSelectPstmt : PreparedStatement
      var nSelectRset : ResultSet
      newPreparedStatement(conn,nestedtableSelect,nSelectPstmt,10)
      echo "nested table select prepared"
      withPreparedStatement(nSelectPstmt):
        nSelectPstmt.executeStatement(nSelectRset) 
        # eval the result columns:
        for i,pt in nSelectRset.resultParamTypeIterator:
          echo "nested_table_column: " & $i & " type: " & $pt
        
        for row in nSelectRset.resultSetRowIterator:       
             echo $row[0].fetchString
             var cr = row.getCollection("TESTCOL")
             var colsize = cr.fetchCollectionSize
             var objRef : OracleObjRef
             echo "collection fetched. numElements " & $colsize
            
             var hexcolumn : string
              
             withOracleCollection(cr):
               for i in 0..colsize-1:
                 var hcol = cr[i].fetchBytes("RAWVALUE")
                 if hcol.isSome:
                   hexcolumn = hcol.get.hex2str
                 else:
                   hexcolumn = $hcol
                 echo $cr[i].fetchDouble("NUMBERVALUE") & " | " &
                   $cr[i].fetchString("STRINGVALUE")  & " | " &
                   $cr[i].fetchString("FIXEDCHARVALUE")  & " | " &
                   $cr[i].fetchDateTime("DATEVALUE")  & " | " &
                   $cr[i].fetchDateTime("TIMESTAMPVALUE")  & " | " & hexcolumn             
                 # access object attributes by attrName or attribute column index
             
      # TODO: try to filter against a nested-table object

      # var demoCallAggr2 = osql""" select * from HR.NDEMO """
      # var callFuncAggr2 : PreparedStatement
      # var callFuncResultAggr2 : ResultSet
      # newPreparedStatement(conn,demoCallAggr2,callFuncAggr2,5)
        
      # withPreparedStatement(callFuncAggr2):
      #  let param1 = callFuncAggr2.addObjectBindParameter(BindIdx(1),colltype,5)
      #  param1.setObject(0,copyOfColl) # todo: consolidate API
      #  callFuncAggr2.executeStatement(callFuncResultAggr2) 

      #  for row in resultSetRowIterator(callFuncResultAggr2):       
      #    echo $row[0].fetchString

      #FIXME: edition based redefinition example
      #FIXME: varray example (getElementValueByIndex)

      # drop tab with nested table
  var dropNDEMOTab = osql"drop table HR.NDEMO "
  conn.executeDDL(dropNDEMOTab)

  echo "releasing object type demo_coll and demo_obj"
  objtype.releaseOracleObjType
  colltype.releaseOracleObjType 

  var dropDemoAggr :  SqlQuery = osql" drop function HR.DEMO_COLAGGR "
  conn.executeDDL dropDemoAggr

  var dropDemoColl : SqlQuery = osql" drop type HR.DEMO_COLL "
  conn.executeDDL dropDemoColl

  var dropDemoObj : SqlQuery = osql" drop type HR.DEMO_OBJ "
  conn.executeDDL(dropDemoObj)


  conn.releaseConnection
  destroyOracleContext(octx)
