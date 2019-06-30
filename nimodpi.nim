import os, strutils
import nimterop/[cimport, git, paths]

# Copyright (c) 2019 Michael Krauter
# MIT-license - please see the LICENSE-file for details.

#[ 
nim oracle wrapper (ODPI-C).

include this file into your project if you like to access an oracle database
(no lib, static binding so far).

This is the low-level wrapper part; so no extra convenience glue logic provided.
Original API-names preserved (structs and function) for easier linkage with the original documentation

]#

const
  baseDir = currentSourcePath.parentDir()/"build"

  srcDir = baseDir/"odpi"

static:
  cDebug()
  cDisableCaching()
  
  gitPull("https://github.com/oracle/odpi.git", outdir = srcDir, plist = """
include/*.h
embed/*.c
src/*
""", checkout = "master") # master is 3.2 so far

cIncludeDir(srcDir/"include")

cOverride:
  # TODO: some structures are silently discarded by ?treesitter?. evaluate why.
  # to get access to it they are manually defined below - unfortunately some
  # dependent objects are overridden too and are defined here (twice) although parsed
  # successfully by nimterop (actually all structs are wrapped here) 
  # TODO: how to compile against a specific odpi-c version? 
  # remark: all names are left original to refer 1:1 to dpi.h
  # overridden objects based actually on v3.2
  type
    dpiExecMode*  = uint32
    dpiOracleTypeNum* = uint32
    dpiNativeTypeNum* = uint32
    dpiCreateMode* = uint32
    dpiAuthMode* = uint32
    dpiPurity* = uint32
    dpiPoolGetMode* = uint8
    dpiStatementType* = uint16
    dpiSubscrGroupingClass* = uint8
    dpiSubscrGroupingType* = uint8
    dpiSubscrNamespace*  = uint32
    dpiSubscrProtocol* = uint32
    dpiSubscrQOS* = uint32
    dpiVisibility* = uint32
  const
    # subscription grouping classes
    DPI_SUBSCR_GROUPING_CLASS_TIME = 1.uint8
    # subscription grouping types
    DPI_SUBSCR_GROUPING_TYPE_SUMMARY  =          1.uint8
    DPI_SUBSCR_GROUPING_TYPE_LAST     =          2.uint8
    # subscription namespaces
    DPI_SUBSCR_NAMESPACE_AQ     =                1.uint32
    DPI_SUBSCR_NAMESPACE_DBCHANGE  =             2.uint32
    # subscription protocols
    DPI_SUBSCR_PROTO_CALLBACK  =                 0.uint32
    DPI_SUBSCR_PROTO_MAIL      =                 1.uint32
    DPI_SUBSCR_PROTO_PLSQL     =                 2.uint32
    DPI_SUBSCR_PROTO_HTTP      =                 3.uint32
    # subscription quality of service
    DPI_SUBSCR_QOS_RELIABLE   =                  0x01.uint32
    DPI_SUBSCR_QOS_DEREG_NFY  =                  0x02.uint32
    DPI_SUBSCR_QOS_ROWIDS     =                  0x04.uint32
    DPI_SUBSCR_QOS_QUERY      =                  0x08.uint32
    DPI_SUBSCR_QOS_BEST_EFFORT =                 0x10.uint32
    # visibility of messages in advanced queuing
    DPI_VISIBILITY_IMMEDIATE  =                  1.uint32
    DPI_VISIBILITY_ON_COMMIT  =                  2.uint32
    # statement types
    DPI_STMT_TYPE_UNKNOWN : dpiStatementType =                      0.uint16
    DPI_STMT_TYPE_SELECT : dpiStatementType =                       1.uint16
    DPI_STMT_TYPE_UPDATE : dpiStatementType =                       2.uint16
    DPI_STMT_TYPE_DELETE : dpiStatementType =                       3.uint16
    DPI_STMT_TYPE_INSERT : dpiStatementType =                       4.uint16
    DPI_STMT_TYPE_CREATE : dpiStatementType =                       5.uint16
    DPI_STMT_TYPE_DROP   : dpiStatementType =                       6.uint16
    DPI_STMT_TYPE_ALTER  : dpiStatementType =                       7.uint16
    DPI_STMT_TYPE_BEGIN  : dpiStatementType =                       8.uint16
    DPI_STMT_TYPE_DECLARE : dpiStatementType =                      9.uint16
    DPI_STMT_TYPE_CALL    : dpiStatementType =                     10.uint16
    DPI_STMT_TYPE_EXPLAIN_PLAN : dpiStatementType =                15.uint16
    DPI_STMT_TYPE_MERGE   : dpiStatementType =                     16.uint16
    DPI_STMT_TYPE_ROLLBACK : dpiStatementType =                    17.uint16
    DPI_STMT_TYPE_COMMIT  : dpiStatementType =                     21.uint16
    # conn pool modes
    DPI_MODE_POOL_GET_WAIT : dpiPoolGetMode =      0.uint8
    DPI_MODE_POOL_GET_NOWAIT : dpiPoolGetMode =    1.uint8
    DPI_MODE_POOL_GET_FORCEGET : dpiPoolGetMode =  2.uint8
    DPI_MODE_POOL_GET_TIMEDWAIT : dpiPoolGetMode = 3.uint8
    # dpi exec modes
    DPI_MODE_EXEC_DEFAULT : dpiExecMode =             0x00000000.uint32
    DPI_MODE_EXEC_DESCRIBE_ONLY : dpiExecMode      =  0x00000010.uint32
    DPI_MODE_EXEC_COMMIT_ON_SUCCESS : dpiExecMode  =  0x00000020.uint32
    DPI_MODE_EXEC_BATCH_ERRORS  : dpiExecMode      =  0x00000080.uint32
    DPI_MODE_EXEC_PARSE_ONLY   : dpiExecMode       =  0x00000100.uint32
    DPI_MODE_EXEC_ARRAY_DML_ROWCOUNTS : dpiExecMode = 0x00100000.uint32
    # generic dpi return values                                 
    DPI_SUCCESS = 0.cint  # returned by all dpi functions
    DPI_FAILURE = -1.cint
    # dpi authentication mode
    DPI_MODE_AUTH_DEFAULT : dpiAuthMode = 0x00000000.uint32
    DPI_MODE_AUTH_SYSDBA : dpiAuthMode = 0x00000002.uint32
    DPI_MODE_AUTH_SYSOPER : dpiAuthMode =0x00000004.uint32
    DPI_MODE_AUTH_PRELIM : dpiAuthMode = 0x00000008.uint32
    DPI_MODE_AUTH_SYSASM : dpiAuthMode = 0x00008000.uint32
    DPI_MODE_AUTH_SYSBKP : dpiAuthMode = 0x00020000.uint32
    DPI_MODE_AUTH_SYSDGD : dpiAuthMode = 0x00040000.uint32
    DPI_MODE_AUTH_SYSKMT : dpiAuthMode = 0x00080000.uint32
    DPI_MODE_AUTH_SYSRAC : dpiAuthMode = 0x00100000.uint32
    # native c types
    DPI_NATIVE_TYPE_INT64 : dpiNativeTypeNum  =                   3000.uint32
    DPI_NATIVE_TYPE_UINT64 :dpiNativeTypeNum =                    3001.uint32
    DPI_NATIVE_TYPE_FLOAT  :dpiNativeTypeNum =                    3002.uint32
    DPI_NATIVE_TYPE_DOUBLE :dpiNativeTypeNum =                    3003.uint32
    DPI_NATIVE_TYPE_BYTES  :dpiNativeTypeNum =                    3004.uint32
    DPI_NATIVE_TYPE_TIMESTAMP :dpiNativeTypeNum=                  3005.uint32
    DPI_NATIVE_TYPE_INTERVAL_DS :dpiNativeTypeNum=                3006.uint32
    DPI_NATIVE_TYPE_INTERVAL_YM :dpiNativeTypeNum=                3007.uint32
    DPI_NATIVE_TYPE_LOB         :dpiNativeTypeNum=                3008.uint32
    DPI_NATIVE_TYPE_OBJECT  :dpiNativeTypeNum    =                3009.uint32
    DPI_NATIVE_TYPE_STMT    :dpiNativeTypeNum    =                3010.uint32
    DPI_NATIVE_TYPE_BOOLEAN :dpiNativeTypeNum    =                3011.uint32
    DPI_NATIVE_TYPE_ROWID   :dpiNativeTypeNum    =                3012.uint32
    # dpi oracle types
    DPI_ORACLE_TYPE_NONE : dpiOracleTypeNum    =                  2000.uint32
    DPI_ORACLE_TYPE_VARCHAR : dpiOracleTypeNum  =                 2001.uint32
    DPI_ORACLE_TYPE_NVARCHAR : dpiOracleTypeNum =                 2002.uint32
    DPI_ORACLE_TYPE_CHAR  : dpiOracleTypeNum    =                 2003.uint32
    DPI_ORACLE_TYPE_NCHAR : dpiOracleTypeNum    =                 2004.uint32
    DPI_ORACLE_TYPE_ROWID : dpiOracleTypeNum    =                 2005.uint32
    DPI_ORACLE_TYPE_RAW   : dpiOracleTypeNum    =                 2006.uint32
    DPI_ORACLE_TYPE_NATIVE_FLOAT : dpiOracleTypeNum  =            2007.uint32
    DPI_ORACLE_TYPE_NATIVE_DOUBLE : dpiOracleTypeNum =            2008.uint32
    DPI_ORACLE_TYPE_NATIVE_INT : dpiOracleTypeNum =               2009.uint32
    DPI_ORACLE_TYPE_NUMBER     : dpiOracleTypeNum =               2010.uint32
    DPI_ORACLE_TYPE_DATE       : dpiOracleTypeNum =               2011.uint32
    DPI_ORACLE_TYPE_TIMESTAMP  : dpiOracleTypeNum =               2012.uint32
    DPI_ORACLE_TYPE_TIMESTAMP_TZ : dpiOracleTypeNum =             2013.uint32
    DPI_ORACLE_TYPE_TIMESTAMP_LTZ : dpiOracleTypeNum =            2014.uint32
    DPI_ORACLE_TYPE_INTERVAL_DS : dpiOracleTypeNum  =             2015.uint32
    DPI_ORACLE_TYPE_INTERVAL_YM : dpiOracleTypeNum =              2016.uint32
    DPI_ORACLE_TYPE_CLOB        : dpiOracleTypeNum =              2017.uint32
    DPI_ORACLE_TYPE_NCLOB       : dpiOracleTypeNum =              2018.uint32
    DPI_ORACLE_TYPE_BLOB        : dpiOracleTypeNum =              2019.uint32
    DPI_ORACLE_TYPE_BFILE       : dpiOracleTypeNum =              2020.uint32
    DPI_ORACLE_TYPE_STMT        : dpiOracleTypeNum =              2021.uint32
    DPI_ORACLE_TYPE_BOOLEAN     : dpiOracleTypeNum =              2022.uint32
    DPI_ORACLE_TYPE_OBJECT      : dpiOracleTypeNum =              2023.uint32
    DPI_ORACLE_TYPE_LONG_VARCHAR : dpiOracleTypeNum =             2024.uint32
    DPI_ORACLE_TYPE_LONG_RAW     : dpiOracleTypeNum =             2025.uint32
    DPI_ORACLE_TYPE_NATIVE_UINT  : dpiOracleTypeNum =             2026.uint32
    DPI_ORACLE_TYPE_MAX          : dpiOracleTypeNum =             2027.uint32
                                                                 
  type                                                                
    DpiSubscrGroupingClass* {.pure.} = enum TIME = DPI_SUBSCR_GROUPING_CLASS_TIME

    DpiSubscrGroupingType* {.pure.} = enum SUMMARY = DPI_SUBSCR_GROUPING_TYPE_SUMMARY,
                                  LAST = DPI_SUBSCR_GROUPING_TYPE_LAST

    DpiSubscrNamespace* {.pure.} = enum AQ = DPI_SUBSCR_NAMESPACE_AQ,
                               DBCHANGE = DPI_SUBSCR_NAMESPACE_DBCHANGE

    DpiSubscrProtocols* {.pure.} = enum CALLBACK = DPI_SUBSCR_PROTO_CALLBACK,
                               MAIL = DPI_SUBSCR_PROTO_MAIL,
                               PLSQL = DPI_SUBSCR_PROTO_PLSQL,
                               HTTP = DPI_SUBSCR_PROTO_HTTP

    DpiSubscrQOS* {.pure.} = enum RELIABLE =DPI_SUBSCR_QOS_RELIABLE ,
                         DEREG_NFY = DPI_SUBSCR_QOS_DEREG_NFY,
                         ROWIDS = DPI_SUBSCR_QOS_ROWIDS,
                         QUERY = DPI_SUBSCR_QOS_QUERY,
                         BEST_EFFORT = DPI_SUBSCR_QOS_BEST_EFFORT 
    DpiVisibility* {.pure.} = enum IMMEDIATE = DPI_VISIBILITY_IMMEDIATE,
                          ON_COMMIT = DPI_VISIBILITY_ON_COMMIT

    DpiStmtType* {.pure.} = enum  UNKNOWN = DPI_STMT_TYPE_UNKNOWN,
                         SELECT = DPI_STMT_TYPE_SELECT,
                         UPDATE = DPI_STMT_TYPE_UPDATE,            
                         DELETE = DPI_STMT_TYPE_DELETE,            
                         INSERT = DPI_STMT_TYPE_INSERT,            
                         CREATE = DPI_STMT_TYPE_CREATE,            
                         DROP   = DPI_STMT_TYPE_DROP,              
                         ALTER  = DPI_STMT_TYPE_ALTER,             
                         BEGIN  = DPI_STMT_TYPE_BEGIN,             
                         DECLARE = DPI_STMT_TYPE_DECLARE,          
                         CALL    = DPI_STMT_TYPE_CALL,             
                         EXPLAIN_PLAN = DPI_STMT_TYPE_EXPLAIN_PLAN,
                         MERGE   = DPI_STMT_TYPE_MERGE,            
                         ROLLBACK = DPI_STMT_TYPE_ROLLBACK,        
                         COMMIT  = DPI_STMT_TYPE_COMMIT            
    
    DpiPoolGetMode* {.pure.} = enum GET_WAIT = DPI_MODE_POOL_GET_WAIT,
                               NOWAIT = DPI_MODE_POOL_GET_NOWAIT,
                               FORCEGET = DPI_MODE_POOL_GET_FORCEGET,
                               TIMEDWAIT = DPI_MODE_POOL_GET_TIMEDWAIT

    DpiModeExec* {.pure.} = enum DEFAULTMODE = DPI_MODE_EXEC_DEFAULT, 
                                      DESCRIBE_ONLY = DPI_MODE_EXEC_DESCRIBE_ONLY, 
                                      COMMIT_ON_SUCCESS = DPI_MODE_EXEC_COMMIT_ON_SUCCESS,
                                      BATCH_ERRORS = DPI_MODE_EXEC_BATCH_ERRORS,
                                      PARSE_ONLY = DPI_MODE_EXEC_PARSE_ONLY,
                                      ARRAY_DML_ROWCOUNTS = DPI_MODE_EXEC_ARRAY_DML_ROWCOUNTS

    DpiResult* {.pure.} = enum FAILURE = DPI_FAILURE, SUCCESS = DPI_SUCCESS 

    DpiAuthMode* {.pure.} = enum DEFAULTAUTHMODE = DPI_MODE_AUTH_DEFAULT,
                                      SYSDBA = DPI_MODE_AUTH_SYSDBA
                                      SYSOPER = DPI_MODE_AUTH_SYSOPER, 
                                      PRELIM = DPI_MODE_AUTH_PRELIM,
                                      SYSASM = DPI_MODE_AUTH_SYSASM,
                                      SYSBKP = DPI_MODE_AUTH_SYSBKP,
                                      SYSDGD = DPI_MODE_AUTH_SYSDGD,
                                      SYSKMT = DPI_MODE_AUTH_SYSKMT,
                                      SYSRAC = DPI_MODE_AUTH_SYSRAC

    DpiOracleTypes* {.pure.} = enum  OTNONE = DPI_ORACLE_TYPE_NONE ,
                                OTVARCHAR = DPI_ORACLE_TYPE_VARCHAR ,
                                OTNVARCHAR = DPI_ORACLE_TYPE_NVARCHAR ,
                                OTCHAR = DPI_ORACLE_TYPE_CHAR ,
                                OTNCHAR = DPI_ORACLE_TYPE_NCHAR ,
                                OTROWID = DPI_ORACLE_TYPE_ROWID ,
                                OTRAW = DPI_ORACLE_TYPE_RAW,
                                OTNATIVE_FLOAT = DPI_ORACLE_TYPE_NATIVE_FLOAT,
                                OTNATIVE_DOUBLE = DPI_ORACLE_TYPE_NATIVE_DOUBLE,
                                OTNATIVE_INT = DPI_ORACLE_TYPE_NATIVE_INT ,
                                OTNUMBER      = DPI_ORACLE_TYPE_NUMBER ,               
                                OTDATE        = DPI_ORACLE_TYPE_DATE ,              
                                OTTIMESTAMP   = DPI_ORACLE_TYPE_TIMESTAMP ,              
                                OTTIMESTAMP_TZ = DPI_ORACLE_TYPE_TIMESTAMP_TZ ,             
                                OTTIMESTAMP_LTZ = DPI_ORACLE_TYPE_TIMESTAMP_LTZ ,            
                                OTINTERVAL_DS  = DPI_ORACLE_TYPE_INTERVAL_DS ,             
                                OTINTERVAL_YM  = DPI_ORACLE_TYPE_INTERVAL_YM ,             
                                OTCLOB         = DPI_ORACLE_TYPE_CLOB ,             
                                OTNCLOB        = DPI_ORACLE_TYPE_NCLOB ,             
                                OTBLOB         = DPI_ORACLE_TYPE_BLOB ,             
                                OTBFILE        = DPI_ORACLE_TYPE_BFILE ,             
                                OTSTMT         = DPI_ORACLE_TYPE_STMT ,             
                                OTBOOLEAN      = DPI_ORACLE_TYPE_BOOLEAN ,             
                                OTOBJECT       = DPI_ORACLE_TYPE_OBJECT ,             
                                OTLONG_VARCHAR = DPI_ORACLE_TYPE_LONG_VARCHAR ,             
                                OTLONG_RAW     = DPI_ORACLE_TYPE_LONG_RAW ,             
                                OTNATIVE_UINT  = DPI_ORACLE_TYPE_NATIVE_UINT ,             
                                OTMAX          = DPI_ORACLE_TYPE_MAX             

    DpiNativeCTypes*  {.pure.} = enum NativeINT64 = DPI_NATIVE_TYPE_INT64,
                                NativeUINT64 = DPI_NATIVE_TYPE_UINT64,
                                NativeFLOAT = DPI_NATIVE_TYPE_FLOAT,
                                NativeDOUBLE = DPI_NATIVE_TYPE_DOUBLE, 
                                NativeBYTES = DPI_NATIVE_TYPE_BYTES,
                                NativeTIMESTAMP =  DPI_NATIVE_TYPE_TIMESTAMP,
                                NativeINTERVAL_DS = DPI_NATIVE_TYPE_INTERVAL_DS,
                                NativeINTERVAL_YM = DPI_NATIVE_TYPE_INTERVAL_YM,
                                NativeLOB =  DPI_NATIVE_TYPE_LOB,
                                NativeOBJECT = DPI_NATIVE_TYPE_OBJECT,
                                NativeSTMT = DPI_NATIVE_TYPE_STMT,
                                NativeBOOLEAN = DPI_NATIVE_TYPE_BOOLEAN,
                                NativeROWID =   DPI_NATIVE_TYPE_ROWID
  type
    dpiPool* {.importc, header: "dpi.h".} = object
    dpiLob* {.importc, header: "dpi.h".} = object
    dpiObject* {.importc, header: "dpi.h".} = object
    dpiRowid* {.importc, header: "dpi.h".} = object
    dpiStmt* {.importc,header:"dpi.h".} = object
    dpiObjectType* {.importc,header:"dpi.h".} = object

    dpiErrorInfo* {.pure,final.} = object
      code* : int32
      offset* : uint16
      message* : cstring
      messageLength* : uint32
      encoding* : cstring
      fnName* : cstring
      action* : cstring
      sqlState* : cstring
      isRecoverable* : cint

    # obj used for providing metadata about data types
    dpiDataTypeInfo* {.pure,final.} = object
      oracleTypeNum* : dpiOracleTypeNum
      defaultNativeTypeNum* : dpiNativeTypeNum
      ociTypeCode* : uint16
      dbSizeInBytes* : uint32
      clientSizeInBytes* : uint32
      sizeInChars* : uint32
      precision* : int16
      scale* : int8
      fsPrecision* : uint8
      objectType* : ptr dpiObjectType

    # obj used for transferring object attribute information from ODPI-C 
    dpiObjectAttrInfo* {.pure,final.} = object 
      name* : cstring
      nameLength* : uint32
      typeInfo* : dpiDataTypeInfo

    # obj used for transferring object type information from ODPI-C
    dpiObjectTypeInfo* {.pure,final.} = object
      schema* : cstring
      schemaLength* : uint32
      name* : cstring
      nameLength* : uint32
      isCollection* : cint
      elementTypeInfo* : dpiDataTypeInfo
      numAttributes* : uint16

    # obj used for creating pools
    dpiPoolCreateParams* {.pure,final} = object
      minSessions : uint32
      maxSessions : uint32
      sessionIncrement : uint32
      pingInterval : cint
      pingTimeout : cint
      homogeneous : cint
      externalAuth : cint
      getMode : dpiPoolGetMode
      outPoolName : cstring
      outPoolNameLength : uint32
      timeout : uint32
      waitTimeout : uint32
      maxLifetimeSession : uint32
      plsqlFixupCallback : cstring
      plsqlFixupCallbackLength : uint32

    dpiVersionInfo* {.pure,final.} = object
      versionNum* : cint
      releaseNum* : cint
      updateNum* : cint
      portReleaseNum* : cint
      portUpdateNum* : cint
      fullVersionNum* : uint32

    dpiCommonCreateParams* {.pure,final.} = object
      createMode* : dpiCreateMode
      encoding* : cstring
      nencoding* : cstring
      edition* : cstring
      editionLength* : uint32
      driverName* : cstring
      driverNameLength* : uint32

    # obj used for transferring encoding information from ODPI-C
    dpiEncodingInfo* {.pure,final.} = object
      encoding* : cstring
      maxBytesPerCharacter* : int32
      nencoding* : cstring
      nmaxBytesPerCharacter* : int32

    dpiAppContext* {.pure,final.} = object
      namespaceName* : cstring
      namespaceNameLength* : uint32
      name* : cstring
      nameLength* : uint32
      value* : cstring
      valueLength* : uint32
    
    # obj used for transferring query metadata from ODPI-C
    dpiQueryInfo* {.pure,final.} = object
      name* : cstring
      nameLength* : uint32
      typeInfo* : dpiDataTypeInfo
      nullOk* : cint

    # obj used for transferring statement information from ODPI-C
    dpiStmtInfo* {.pure,final.} = object
      isQuery : cint
      isPLSQL : cint
      isDDL : cint
      isDML : cint
      statementType : dpiStatementType
      isReturning : cint

    dpiIntervalDS* {.pure,final} = object
      days*: int32
      hours*: int32
      minutes*: int32
      seconds*: int32
      fseconds*: int32

    #  structure used for transferring years/months intervals to/from ODPI-C
    dpiIntervalYM* {.pure,final} = object
      years*: int32
      months*: int32

    #  structure used for transferring dates to/from ODPI-C
    dpiTimestamp* {.pure,final} = object
      year*: int16
      month*: uint8
      day*: uint8
      hour*: uint8
      minute*: uint8
      second*: uint8
      fsecond*: uint32
      tzHourOffset*: int8
      tzMinuteOffset*: int8
 
    dpiBytes* {.pure,final} = object
      `ptr`*: cstring
      length*: uint32
      encoding*: cstring
 
    dpiDataBuffer* {.pure,final.} = object {.union.}
      asBoolean*: cint
      asInt64*: int64
      asUint64*: uint64
      asFloat*: cfloat
      asDouble*: cdouble
      asBytes*: dpiBytes
      asTimestamp*: dpiTimestamp
      asIntervalDS*: dpiIntervalDS
      asIntervalYM*: dpiIntervalYM
      asLOB*: ptr dpiLob
      asObject*: ptr dpiObject
      asStmt*: ptr dpiStmt
      asRowid*: ptr dpiRowid

    dpiData*  {.pure,final.} = object
      isNull* : cint
      value*  : dpiDataBuffer

    dpiShardingKeyColumn* {.pure,final.} = object
      oracleTypeNum* : dpiOracleTypeNum
      nativeTypeNum* : dpiNativeTypeNum
      value* : dpiDataBuffer

    dpiConnCreateParams* {.pure,final.} = object
      authMode* : dpiAuthMode
      connectionClass* : cstring
      connectionClassLength* : uint32
      purity* : dpiPurity
      newPassword* : cstring
      newPasswordLength* : uint32
      appContext* : ptr dpiAppContext
      numAppContext* : uint32
      externalAuth* : cint
      externalHandle* : pointer
      pool* : ptr dpiPool
      tag* : cstring
      tagLength* : uint32
      matchAnyTag* : cint
      outTag* : cstring
      outTagLength* : uint32
      outTagFound* : cint
      shardingKeyColumns* : ptr dpiShardingKeyColumn
      numShardingKeyColumns* : uint8
      superShardingKeyColumns* : ptr dpiShardingKeyColumn
      numSuperShardingKeyColumns* : uint8 
      outNewSession* : cint

include odpiutils

cCompile(srcDir/"/embed/dpi.c")

cImport(srcDir/"/include/dpi.h", recurse = true)
