# toString procs
proc `$`*(p : var SqlQuery) : string = 
  $p.rawSql

proc `$`*(p: var dpiStmtInfo): string =
  ## string repr of a statementInfo obj
  "dpiStatementInfo: isQuery " & $p.isQuery & " isPlSql: " & $p.isPLSQL &
  " isDDL: " & $p.isDDL & " isDML: " & $p.isDML & " isReturning: " &
    $p.isReturning & " " & $DpiStmtType(p.statementType)

proc `$`*(p: var dpiQueryInfo): string =
  ## string repr of the dpiQueryInfo obj
  "dpiQueryInfo: name " & $p.name & " namelen: " & $p.nameLength &
  " nullok: " & $p.nullOk 
      
proc `$`*(p: var dpiDataTypeInfo): string =
  ## string repr of the dpiDataTypeInfo obj / not all vals exposed
  "dpiDataTypeInfo: oracleTypeNum " & $DpiOracleType(p.oracleTypeNum) & 
  " defaultNativeTypeNum: " & $DpiNativeCType(p.defaultNativeTypeNum) &
  " dbsize_bytes: " & $p.dbSizeInBytes & " clientsize_bytes " & $p.clientSizeInBytes 

proc `$`* (p: var dpiTimestamp): string =
  ## string representation of a timestamp column
  "dpiTimestamp: year:" & $p.year & " month:" & $p.month & " day:" & $p.day & 
  " hour: " & $p.hour & " minute:" & $p.minute & " second:" & $p.second & 
  " fsecond:" & $p.fsecond &
  " tzHOffset:" & $p.tzHourOffset & " tzMinOffset:" & $p.tzMinuteOffset
