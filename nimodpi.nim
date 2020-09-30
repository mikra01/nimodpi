import os
import nimterop/[build, cimport]

# Copyright (c) 2019 Michael Krauter
# MIT-license - please see the LICENSE-file for details.

#[ 
nim oracle wrapper (ODPI-C).

include this file into your project if you like to access an oracle database
(no lib, static binding so far).

This is the low-level wrapper part; so no extra convenience glue logic provided.
Original API-names preserved (structs and function) for easier linkage with the original documentation.

if you like a higher-level wrapper, include db_oracle into your project.

]#

const
  baseDir = currentSourcePath.parentDir()/"build"

  srcDir = baseDir/"odpi"

static:
  cDebug()
  cDisableCaching()

  gitPull("https://github.com/oracle/odpi.git", outdir = srcDir,
      plist = """
include/*.h
embed/*.c
src/*
""", checkout = "master") # master is 3.2 so far
  # if a specific version is desired, pull the odpi version manually into the 
  # subdirectory /build/

cIncludeDir(srcDir/"include")

cOverride:
  type
    DpiOracleType* {.pure.} = enum OTNONE = DPI_ORACLE_TYPE_NONE,
                                OTVARCHAR = DPI_ORACLE_TYPE_VARCHAR,
                                OTNVARCHAR = DPI_ORACLE_TYPE_NVARCHAR,
                                OTCHAR = DPI_ORACLE_TYPE_CHAR,
                                OTNCHAR = DPI_ORACLE_TYPE_NCHAR,
                                OTROWID = DPI_ORACLE_TYPE_ROWID,
                                OTRAW = DPI_ORACLE_TYPE_RAW,
                                OTNATIVE_FLOAT = DPI_ORACLE_TYPE_NATIVE_FLOAT,
                                OTNATIVE_DOUBLE = DPI_ORACLE_TYPE_NATIVE_DOUBLE,
                                OTNATIVE_INT = DPI_ORACLE_TYPE_NATIVE_INT,
                                OTNUMBER = DPI_ORACLE_TYPE_NUMBER,
                                OTDATE = DPI_ORACLE_TYPE_DATE,
                                OTTIMESTAMP = DPI_ORACLE_TYPE_TIMESTAMP,
                                OTTIMESTAMP_TZ = DPI_ORACLE_TYPE_TIMESTAMP_TZ,
                                OTTIMESTAMP_LTZ = DPI_ORACLE_TYPE_TIMESTAMP_LTZ,
                                OTINTERVAL_DS = DPI_ORACLE_TYPE_INTERVAL_DS,
                                OTINTERVAL_YM = DPI_ORACLE_TYPE_INTERVAL_YM,
                                OTCLOB = DPI_ORACLE_TYPE_CLOB,
                                OTNCLOB = DPI_ORACLE_TYPE_NCLOB,
                                OTBLOB = DPI_ORACLE_TYPE_BLOB,
                                OTBFILE = DPI_ORACLE_TYPE_BFILE,
                                OTSTMT = DPI_ORACLE_TYPE_STMT,
                                OTBOOLEAN = DPI_ORACLE_TYPE_BOOLEAN,
                                OTOBJECT = DPI_ORACLE_TYPE_OBJECT,
                                OTLONG_VARCHAR = DPI_ORACLE_TYPE_LONG_VARCHAR,
                                OTLONG_RAW = DPI_ORACLE_TYPE_LONG_RAW,
                                OTNATIVE_UINT = DPI_ORACLE_TYPE_NATIVE_UINT,
                                OTMAX = DPI_ORACLE_TYPE_MAX

    DpiNativeCType* {.pure.} = enum INT64 = DPI_NATIVE_TYPE_INT64,
                                UINT64 = DPI_NATIVE_TYPE_UINT64,
                                FLOAT = DPI_NATIVE_TYPE_FLOAT,
                                DOUBLE = DPI_NATIVE_TYPE_DOUBLE,
                                BYTES = DPI_NATIVE_TYPE_BYTES,
                                TIMESTAMP = DPI_NATIVE_TYPE_TIMESTAMP,
                                INTERVAL_DS = DPI_NATIVE_TYPE_INTERVAL_DS,
                                INTERVAL_YM = DPI_NATIVE_TYPE_INTERVAL_YM,
                                LOB = DPI_NATIVE_TYPE_LOB,
                                OBJECT = DPI_NATIVE_TYPE_OBJECT,
                                STMT = DPI_NATIVE_TYPE_STMT,
                                BOOLEAN = DPI_NATIVE_TYPE_BOOLEAN,
                                ROWID = DPI_NATIVE_TYPE_ROWID

    DpiStmtType* {.pure.} = enum UNKNOWN = DPI_STMT_TYPE_UNKNOWN,
                         SELECT = DPI_STMT_TYPE_SELECT,
                         UPDATE = DPI_STMT_TYPE_UPDATE,
                         DELETE = DPI_STMT_TYPE_DELETE,
                         INSERT = DPI_STMT_TYPE_INSERT,
                         CREATE = DPI_STMT_TYPE_CREATE,
                         DROP = DPI_STMT_TYPE_DROP,
                         ALTER = DPI_STMT_TYPE_ALTER,
                         BEGIN = DPI_STMT_TYPE_BEGIN,
                         DECLARE = DPI_STMT_TYPE_DECLARE,
                         CALL = DPI_STMT_TYPE_CALL,
                         EXPLAIN_PLAN = DPI_STMT_TYPE_EXPLAIN_PLAN,
                         MERGE = DPI_STMT_TYPE_MERGE,
                         ROLLBACK = DPI_STMT_TYPE_ROLLBACK,
                         COMMIT = DPI_STMT_TYPE_COMMIT

    DpiResult* {.pure.} = enum FAILURE = DPI_FAILURE, SUCCESS = DPI_SUCCESS

    DpiAuthMode* {.pure.} = enum DEFAULTAUTHMODE = DPI_MODE_AUTH_DEFAULT,
                                      SYSDBA = DPI_MODE_AUTH_SYSDBA,
                                      SYSOPER = DPI_MODE_AUTH_SYSOPER,
                                      PRELIM = DPI_MODE_AUTH_PRELIM,
                                      SYSASM = DPI_MODE_AUTH_SYSASM,
                                      SYSBKP = DPI_MODE_AUTH_SYSBKP,
                                      SYSDGD = DPI_MODE_AUTH_SYSDGD,
                                      SYSKMT = DPI_MODE_AUTH_SYSKMT,
                                      SYSRAC = DPI_MODE_AUTH_SYSRAC

    DpiOracleType* {.pure.} = enum OTNONE = DPI_ORACLE_TYPE_NONE,
                                OTVARCHAR = DPI_ORACLE_TYPE_VARCHAR,
                                OTNVARCHAR = DPI_ORACLE_TYPE_NVARCHAR,
                                OTCHAR = DPI_ORACLE_TYPE_CHAR,
                                OTNCHAR = DPI_ORACLE_TYPE_NCHAR,
                                OTROWID = DPI_ORACLE_TYPE_ROWID,
                                OTRAW = DPI_ORACLE_TYPE_RAW,
                                OTNATIVE_FLOAT = DPI_ORACLE_TYPE_NATIVE_FLOAT,
                                OTNATIVE_DOUBLE = DPI_ORACLE_TYPE_NATIVE_DOUBLE,
                                OTNATIVE_INT = DPI_ORACLE_TYPE_NATIVE_INT,
                                OTNUMBER = DPI_ORACLE_TYPE_NUMBER,
                                OTDATE = DPI_ORACLE_TYPE_DATE,
                                OTTIMESTAMP = DPI_ORACLE_TYPE_TIMESTAMP,
                                OTTIMESTAMP_TZ = DPI_ORACLE_TYPE_TIMESTAMP_TZ,
                                OTTIMESTAMP_LTZ = DPI_ORACLE_TYPE_TIMESTAMP_LTZ,
                                OTINTERVAL_DS = DPI_ORACLE_TYPE_INTERVAL_DS,
                                OTINTERVAL_YM = DPI_ORACLE_TYPE_INTERVAL_YM,
                                OTCLOB = DPI_ORACLE_TYPE_CLOB,
                                OTNCLOB = DPI_ORACLE_TYPE_NCLOB,
                                OTBLOB = DPI_ORACLE_TYPE_BLOB,
                                OTBFILE = DPI_ORACLE_TYPE_BFILE,
                                OTSTMT = DPI_ORACLE_TYPE_STMT,
                                OTBOOLEAN = DPI_ORACLE_TYPE_BOOLEAN,
                                OTOBJECT = DPI_ORACLE_TYPE_OBJECT,
                                OTLONG_VARCHAR = DPI_ORACLE_TYPE_LONG_VARCHAR,
                                OTLONG_RAW = DPI_ORACLE_TYPE_LONG_RAW,
                                OTNATIVE_UINT = DPI_ORACLE_TYPE_NATIVE_UINT,
                                OTMAX = DPI_ORACLE_TYPE_MAX

    DpiNativeCType* {.pure.} = enum INT64 = DPI_NATIVE_TYPE_INT64,
                                UINT64 = DPI_NATIVE_TYPE_UINT64,
                                FLOAT = DPI_NATIVE_TYPE_FLOAT,
                                DOUBLE = DPI_NATIVE_TYPE_DOUBLE,
                                BYTES = DPI_NATIVE_TYPE_BYTES,
                                TIMESTAMP = DPI_NATIVE_TYPE_TIMESTAMP,
                                INTERVAL_DS = DPI_NATIVE_TYPE_INTERVAL_DS,
                                INTERVAL_YM = DPI_NATIVE_TYPE_INTERVAL_YM,
                                LOB = DPI_NATIVE_TYPE_LOB,
                                OBJECT = DPI_NATIVE_TYPE_OBJECT,
                                STMT = DPI_NATIVE_TYPE_STMT,
                                BOOLEAN = DPI_NATIVE_TYPE_BOOLEAN,
                                ROWID = DPI_NATIVE_TYPE_ROWID
    DpiModeExec* {.pure.} = enum DEFAULTMODE = DPI_MODE_EXEC_DEFAULT,
                                      DESCRIBE_ONLY = DPI_MODE_EXEC_DESCRIBE_ONLY,
                                      COMMIT_ON_SUCCESS = DPI_MODE_EXEC_COMMIT_ON_SUCCESS,
                                      BATCH_ERRORS = DPI_MODE_EXEC_BATCH_ERRORS,
                                      PARSE_ONLY = DPI_MODE_EXEC_PARSE_ONLY,
                                      ARRAY_DML_ROWCOUNTS = DPI_MODE_EXEC_ARRAY_DML_ROWCOUNTS
  
cCompile(srcDir/"/embed/dpi.c")
cImport(srcDir/"/include/dpi.h", recurse = true)
