# this file contains various object to string repr conversion
# procs

const hChars = "0123456789ABCDEF"

proc hex2Str*(par: var openArray[byte]): string =
  result = newString(2 + ((par.len) shl 1)) # len mul 2 plus 2 extra chars
  result[0] = '0'
  result[1] = 'x'
  for i in countup(0, par.len-1):
    result[2 + cast[int](i shl 1)] =
      hChars[cast[int](par[i] shr 4)] # process hs nibble
    result[3 + cast[int](i shl 1)] =
      hChars[cast[int](par[i] and 0xF)] # process ls nibble

# toString procs
proc fetchObjectTypeName(p : var dpiObjectTypeInfo) : string =
  result = newString(p.nameLength+p.schemaLength+1)
  copyMem(addr(result[0]),p.schema,p.schemaLength)
  result[p.schemaLength] = '.'
  copyMem(addr(result[p.schemaLength+1]),p.name,p.nameLength)


template `$`*(p : var SqlQuery) : string = 
  $p

template `$`*(p: var dpiStmtInfo): string =
  ## string repr of a statementInfo obj
  "dpiStatementInfo: isQuery " & $p.isQuery & " isPlSql: " & $p.isPLSQL &
  " isDDL: " & $p.isDDL & " isDML: " & $p.isDML & " isReturning: " &
    $p.isReturning & " " & $DpiStmtType(p.statementType)

template `$`*(p: var dpiQueryInfo): string =
  ## string repr of the dpiQueryInfo obj
  "dpiQueryInfo: name " & $p.name & " namelen: " & $p.nameLength &
  " nullok: " & $p.nullOk 
      
template `$`*(p: var dpiDataTypeInfo): string =
  ## string repr of the dpiDataTypeInfo obj / not all vals exposed
  "dpiDataTypeInfo: oracleTypeNum " & $DpiOracleType(p.oracleTypeNum) & 
  " defaultNativeTypeNum: " & $DpiNativeCType(p.defaultNativeTypeNum) &
  " dbsize_bytes: " & $p.dbSizeInBytes & " clientsize_bytes " & $p.clientSizeInBytes 

template fetchCollectionChildType ( p : var dpiObjectTypeInfo ) : ptr dpiObjectType =  
  p.elementTypeInfo.objectType

template `$`*(p: var dpiObjectTypeInfo) : string = 
  ## string repr of the dpiObjectTypeInfo 
  var objtype : ptr dpiObjectType = fetchCollectionChildType(p)
  var objtypeinfo : dpiObjectTypeInfo 
  var childobjtypename : string = ""
  if not objtype.isNil:
    # in case of collection fetch the child type
    discard dpiObjectType_getInfo(objtype,objtypeinfo.addr)
    childobjtypename = fetchObjectTypeName(objtypeinfo)
  "dpiObjectTypeInfo: " & fetchObjectTypeName(p) & " num_attr: " & $p.numAttributes &
  " elementTypeInfo: " & $p.elementTypeInfo & " childtype: " & childobjtypename


template `$`* (p: var dpiTimestamp): string =
  ## string representation of a timestamp column
  "dpiTimestamp: year:" & $p.year & " month:" & $p.month & " day:" & $p.day & 
  " hour: " & $p.hour & " minute:" & $p.minute & " second:" & $p.second & 
  " fsecond:" & $p.fsecond &
  " tzHOffset:" & $p.tzHourOffset & " tzMinOffset:" & $p.tzMinuteOffset

template `$`*(p: var ColumnType): string =
  "dbType:" & $p.dbType & " nativeType:" & $p.nativeType

template `$`*(p: var BindInfo): string =
  var bt : string
  if p.kind == BindInfoType.byPosition:
    bt = "by_position num: " & $p.paramVal.int
  else:
    bt = "by_name: "& $p.paramName
  "bindinfo: " & bt  

template `$`*(p: ref OracleObjType ): string =
    ## string representation OracleObjType
    " schema: " & $p.objectTypeInfo.schema & 
    " name: " & $p.objectTypeInfo.name &
    " isCollection: " & $p.objectTypeInfo.isCollection & 
    " numAttributes " & $p.objectTypeInfo.numAttributes &
    $p.objectTypeInfo.elementTypeInfo 

template `$`*(p: ParamTypeRef): string =
  $p.bindPosition & " " & $p.columnType & " rowbuffersize: " & $p.rowbuffersize

proc `$`*(p: ptr dpiRowId): string =
  ## string representation of the rowid (10byte) - base64 encoded
  var str : cstring = "                    " #20 chars
  var cstringlen : uint32
  discard dpiRowid_getStringValue(p,str.addr,cstringlen.addr)
  return $str

template `$`*(p: Option[string]): string =
  if p.isNone:
    "<dbNull>"
  else:
    $p.get

template `$`*(p: Option[int64]): string =
  if p.isNone:
    "<dbNull>"
  else:
    $p.get    

template `$`*(p: Option[uint64]): string =
  if p.isNone:
    "<dbNull>"
  else:
    $p.get    

template `$`*(p: Option[float32]): string =
  if p.isNone:
    "<dbNull>"
  else:
    $p.get    
            
template `$`*(p: Option[float64]): string =
  if p.isNone:
    "<dbNull>"
  else:
    $p.get    

template `$`*(p: Option[DateTime]): string =
  if p.isNone:
    "<dbNull>"
  else:
    $p.get    
    