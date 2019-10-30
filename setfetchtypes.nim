# fetching/setting templates for raw odpi-c access
# and nim types ParamTypeRef, OracleObj 
template fetchBoolean*(val : ptr dpiData) : Option[bool] =
    ## fetches the specified value as boolean. the value is copied
    if val.isDbNull:
      none(bool)
    else:
      some(val.value.asBoolean)

template fetchBoolean*(param : ParamTypeRef) : Option[bool] =
  ## fetches the sepcified value as boolean by index 0
  param[0].fetchBoolean

template fetchBoolean*( param : OracleObj , index : int) : Option[bool] =
  ## access template for db-types
  getAttributeValue(param,index).fetchBoolean

template fetchBoolean*( param : OracleObj , attrName : string) : Option[bool] =
  ## access template for db-types
  getAttributeValue(param,lookUpAttrIndexByName(attrName)).fetchBoolean
  
template setBoolean*(param : ptr dpiData, value : Option[bool] ) =
    ## bind parameter setter boolean type.
    if value.isNone:
       param.setDbNull
    else: 
       param.setNotDbNull  
       param.value.asBoolean = value.get 

template setBoolean*( param : ParamTypeRef, value : Option[bool]) =
  ## access template for single bind variables (index 0)
  param[0].setBoolean(value)      

template setBoolean*( param : OracleObj , index : int,  value : Option[bool]) =
  ## access template for db-types
  param[index].setBoolean(value)
  setAttributeValue(param,index)

template setBoolean*( param : OracleObj , attrName : string,  value : Option[bool]) =
  ## access template for db-types
  setBoolean(param,lookUpAttrIndexByName(param,attrName),value)

# simple type conversion templates.
template fetchFloat*(val : ptr dpiData) : Option[float32] =
    ## fetches the specified value as float. the value is copied 
    if val.isDbNull:
      none(float32)
    else:
      some(val.value.asFloat.float32)
  
template fetchFloat*( param : ParamTypeRef) : Option[float32] =
  param[0].fetchFloat

template fetchFloat*( param : OracleObj , index : int) : Option[float] =
  ## access template for db-types
  getAttributeValue(param,index).fetchFloat
  
template fetchFloat*( param : OracleObj , attrName : string) : Option[float32] =
  ## access template for db-types
  getAttributeValue(param,lookUpAttrIndexByName(attrName)).fetchFloat

proc setFloat*( param : ptr dpiData, value : Option[float32]) =
    ## bind parameter setter float32 type. 
    ## TODO: eval why template is not compiling
    if value.isNone: 
      param.setDbNull
    else:
      param.setNotDbNull  
      param.value.asFloat = value.get
  
template setFloat*(param : ParamTypeRef, value : Option[float32]) =
  param[0].setFloat(value)

template setFloat*( param : OracleObj , index : int,  value : Option[float32]) =
  ## access template for db-types
  param[index].setFloat(value)
  setAttributeValue(param,index)

template setFloat*( param : OracleObj , attrName : string,  value : Option[float32]) =
  setFloat(param,lookUpAttrIndexByName(param,attrName),value)

template fetchDouble*(val : ptr dpiData) : Option[float64] =
    ## fetches the specified value as double (Nims 64 bit type). the value is copied 
    if val.isDbNull:
      none(float64)
    else:
      some(val.value.asDouble.float64)

template fetchDouble*( param : ParamTypeRef ) : Option[float64] =
  param[0].fetchDouble  
  
template fetchDouble*( param : OracleObj , index : int) : Option[float64] =
  ## access template for db-types
  getAttributeValue(param,index).fetchDouble

template fetchDouble*( param : OracleObj , attrName : string) : Option[float64] =
  ## access template for db-types
  getAttributeValue(param,lookUpAttrIndexByName(attrName)).fetchDouble

proc setDouble*(param : ptr dpiData, value : Option[float64]) =
    ## bind parameter setter float64 type. 
    ## TODO: eval why template type is not compiling - string types are ok
    if value.isNone:
      param.setDbNull
    else:  
      param.setNotDbNull
      param.value.asDouble = value.get   

template setDouble*( param : ParamTypeRef, value : Option[float64] ) =
  ## convenience template for accessing the first parameter within the buffer
  param[0].setDouble(value)
      
template setDouble*( param : OracleObj , index : int,  value : Option[float64]) =
  ## access template for db-types
  param[index].setDouble(value)
  setAttributeValue(param,index)

template setDouble*( param : OracleObj , attrName : string,  value : Option[float64]) =
  ## access template for db-types
  setDouble(param,lookUpAttrIndexByName(param,attrName),value)

template fetchUInt64*(val : ptr dpiData) : Option[uint64] =
    ## fetches the specified value as double (Nims 64 bit type). the value is copied 
    if val.isDbNull:
      none(uint64)
    else:
      some(val.value.asUint64)

template fetchUInt64*( param : ParamTypeRef ) : Option[uint64] =
  param[0].fetchUInt64

template fetchUInt64*( param : OracleObj, index : int ) : Option[uint64] =
  getAttributeValue(param,index).fetchUInt64

template fetchUInt64*( param : OracleObj , attrName : string) : Option[uint64] =
  ## access template for db-types
  getAttributeValue(param,lookUpAttrIndexByName(attrName)).fetchUInt64

template setUInt64*(param : ptr dpiData, value : Option[uint64]) =
    ## bind parameter setter uint64 type. 
    if value.isNone:
      param.setDbNull
    else:
      param.setNotDbNull  
      param.value.asUint64 = value.get

template setUInt64*( param : ParamTypeRef, value : Option[uint64] ) =
  ## convenience template for accessing the first parameter within the buffer
  param[0].setUInt64(value)

template setUInt64*( param : OracleObj , index : int,  value : Option[uint64]) =
  ## access template for db-types
  param[index].setUInt64(value)
  setAttributeValue(param,index)
  
template setUInt64*( param : OracleObj , attrName : string,  value : Option[uint64]) =
  ## access template for db-types
  setUInt64(param,lookUpAttrIndexByName(param,attrName),value)

template fetchInt64*(val : ptr dpiData) : Option[int64] =
    ## fetches the specified value as double (Nims 64 bit type). the value is copied 
    if val.isDbNull:
      none(int64)
    else:
      some(val.value.asInt64)

template fetchInt64*( param : ParamTypeRef ) : Option[int64] =
  param[0].fetchInt64

template fetchInt64*( param : OracleObj , index : int) : Option[int64] =
  ## access template for db-types
  getAttributeValue(param,index).fetchInt64

template fetchInt64*( param : OracleObj , attrName : string) : Option[int64] =
  ## access template for db-types
  getAttributeValue(param,lookUpAttrIndexByName(attrName)).fetchInt64

proc setInt64*( param : ptr dpiData, value : Option[int64]) =
     ## bind parameter setter int64 type. 
     if value.isNone:
       param.setDbNull
     else:  
       param.setNotDbNull
       param.value.asInt64  = value.get   

template setInt64*( param : ParamTypeRef, value :  Option[int64] )  =
  ## convenience template for accessing the first parameter within the buffer
  param[0].setInt64(value)

template setInt64*( param : OracleObj , index : int,  value : Option[int64]) =
  ## access template for db-types
  param[index].setInt64(value)
  setAttributeValue(param,index)

template setInt64*( param : OracleObj , attrName : string,  value : Option[int64]) =
  ## access template for db-types
  setInt64(param,lookUpAttrIndexByName(param,attrName),value)

template fetchIntervalDS*(val : ptr dpiData ) : Option[Duration] =
    # todo: implement
    if val.isDbNull:
      none(Duration)
    else:
      some(val.toIntervalDs)

template fetchIntervalDS*(param : ParamTypeRef) : Option[Duration] =
  param[0].fetchIntervalDS     

template fetchIntervalDS*( param : OracleObj , index : int) : Option[Duration] =
  ## access template for db-types
  getAttributeValue(param,index).fetchIntervalDS

template fetchIntervalDS*( param : OracleObj , attrName : string) : Option[Duration] =
  ## access template for db-types
  getAttributeValue(param,lookUpAttrIndexByName(attrName)).fetchIntervalDS

template setIntervalDS*(param : ptr dpiData , value : Option[Duration]) =
    ## bind parameter setter IntervalDS type. this setter operates always with index 1
    if value.isNone:
      param.setDbNull
    else:  
      param.setNotDbNull
      param.value.asIntervalDS.fseconds = value.get.nanoseconds    
      param.value.asIntervalDS.seconds = value.get.seconds 
      param.value.asIntervalDS.minutes = value.get.minutes
      param.value.asIntervalDS.hours = value.get.hours
      param.value.asIntervalDS.days = value.get.days
    
template setIntervalDS*( param : ParamTypeRef, value : Option[Duration]) =
  param[0].setIntervalDS(value)

template setIntervalDS*( param : OracleObj , index : int,  value : Option[Duration]) =
  ## access template for db-types
  param[index].setIntervalDS(value)
  setAttributeValue(param,index)

template setIntervalDS*( param : OracleObj , attrName : string,  value : Option[Duration]) =
  ## access template for db-types
  setIntervalDS(param,lookUpAttrIndexByName(param,attrName),value)

template fetchDateTime*( val : ptr dpiData ) : Option[DateTime] =
    ## fetches the specified value as DateTime. the value is copied 
    if val.isDbNull:
      none(DateTime)
    else:
      some(toDateTime(val))
  
template fetchDateTime*( param: ParamTypeRef) : Option[DateTime] =
  param[0].fetchDateTime

template fetchDateTime*( param : OracleObj , index : int) : Option[DateTime] =
  ## access template for db-types
  getAttributeValue(param,index).fetchDateTime

template fetchDateTime*( param : OracleObj , attrName : string) : Option[DateTime] =
  ## access template for db-types
  getAttributeValue(param,lookUpAttrIndexByName(attrName)).fetchDateTime

proc setDateTime*(param : ptr dpiData , value : Option[DateTime] ) = 
    ## bind parameter setter DateTime type. this setter operates always with index 1
    if value.isNone:
      param.setDbNull
    else:
      param.setNotDbNull  
      let dt = value.get
      let utcoffset = dt.utcOffset
      let tz = dt.timezone
      param.value.asTimestamp.year = dt.year.int16
      param.value.asTimestamp.month = dt.month.uint8     
      param.value.asTimestamp.day = dt.monthday.uint8
      param.value.asTimestamp.hour = dt.hour.uint8
      param.value.asTimestamp.minute = dt.minute.uint8
      param.value.asTimestamp.second =  dt.second.uint8
      param.value.asTimestamp.fsecond = dt.nanosecond.uint32
      
      if not tz.isNil:
        let tzhour : int8 =  cast[int8](utcoffset/3600) # get hours and throw fraction away
        param.value.asTimestamp.tzHourOffset = tzhour
        param.value.asTimestamp.tzMinuteOffset = cast[int8]((utcoffset - tzhour*3600)/60)
        # TODO: eval if ok 

template setDateTime*( param : ParamTypeRef, value : Option[DateTime] ) =
  param[0].setDateTime(value)

template setDateTime*( param : OracleObj , index : int,  value : Option[DateTime]) =
  ## access template for db-types
  param[index].setDateTime(value)
  setAttributeValue(param,index)

template setDateTime*( param : OracleObj , attrName : string,  value : Option[DateTime]) =
  setDateTime(param,lookUpAttrIndexByName(param,attrName),value)

template fetchString*( val : ptr dpiData ) : Option[string] =
    ## fetches the specified value as string. the value is copied  
    ## out of the internal buffer
    if val.isDbNull:
      none(string)
    else:
      some(toNimString(val))
  
template fetchString*( param : ParamTypeRef) : Option[string] =
  ## convenience template for accessing the first parameter (index 0)
  param[0].fetchString

# template fetchString*( param : ParamTypeRef, rownum : int) : Option[string] =
#  ## fetches the specified value as string. the value is copied out of the
#  ## internal buffer
#  param[rownum].fetchString

template fetchString*( param : OracleObj , index : int) : Option[string] =
  ## access template for db-types
  getAttributeValue(param,index).fetchString

template fetchString*( param : OracleObj , attrName : string) : Option[string] =
  ## access template for db-types
  getAttributeValue(param,lookUpAttrIndexByName(attrName)).fetchString

template setString*(val : ptr dpiData, value : Option[string]) = 
  ## sets the string of the odpi-data buffer 
  ## directly (setFromBytes bypassed)
  if value.isNone:
    val.setDbNull
  else:
    val.setNotDbNull
    value.get.copyString2DpiData(val)

template setString*(param : ParamTypeRef, value : Option[string]) =
  param[0].setString(value)

template setString*( param : OracleObj , index : int,  value : Option[string]) =
  ## access template for db-types
  param[index].setString(value)
  setAttributeValue(param,index)

template setString*( param : OracleObj , attrName : string,  value : Option[string]) =
  ## access template for db-types
  setString(param,lookUpAttrIndexByName(param,attrName),value)

template fetchBytes*( val : ptr dpiData ) : Option[seq[byte]] =
    ## fetches the specified value as seq[byte]. the byte array is copied
    if val.isDbNull:
      none(seq[byte])
    else:
      some(toNimByteSeq(val))

template fetchBytes*( param : ParamTypeRef ) : Option[seq[byte]] =
  ## convenience template for fetching the value at position 0
  param[0].fetchBytes

template fetchBytes*( param : OracleObj , index : int) : Option[seq[byte]] =
  ## access template for db-types
  getAttributeValue(param,index).fetchBytes

template fetchBytes*( param : OracleObj , attrName : string) : Option[seq[byte]] =
  ## access template for db-types
  getAttributeValue(param,lookUpAttrIndexByName(attrName)).fetchBytes

template setBytes*( val : ptr dpiData, value : Option[seq[byte]] ) = 
  if value.isNone:
    val.setDbNull
  else:
    val.setNotDbNull
    value.get.copySeq2Data(val)

template setBytes*(param : ParamTypeRef, value : Option[seq[byte]]) =
  ## convenience template to access the parameters first row
  param[0].setBytes(value)

template setBytes*( param : OracleObj , index : int,  value : Option[seq[byte]]) =
  ## access template for db-types
  param[index].setBytes(value)
  setAttributeValue(param,index)
  
template setBytes*( param : OracleObj , attrName : string,  value : Option[seq[byte]]) =
  ## access template for db-types
  setBytes(param,lookUpAttrIndexByName(param,attrName),value)

template fetchRowId*( param : ptr dpiData ) : ptr dpiRowid =
    ## fetches the rowId (internal representation).
    param.value.asRowId 
  
template setRowId*(param : ParamTypeRef , rowid : ptr dpiRowid ) =
    ## bind parameter setter boolean type. this setter operates always with index 0
    ## (todo: eval if the rowid could be nil, and add arraybinding-feature)
    if value.isNone:
      param.data.setDbNull
    else:  
      param.buffer.setNotDbNull
      discard dpiVar_setFromRowid(param.paramVar,0,rowid)

template setRowId*(param : ParamTypeRef , rowid : ptr dpiRowid , rownum : int = 0 ) =
  ## bind parameter setter boolean type. this setter operates always with index 0
  ## (todo: eval if the rowid could be nil, and add arraybinding-feature)
  if value.isNone:
    param.data.setDbNull
  else:  
    param.buffer.setNotDbNull
    discard dpiVar_setFromRowid(param.paramVar,rownum.uint32,rowid)
    

template fetchRefCursor*(param : ptr dpiData ) : ptr dpiStmt =
    ## fetches a refCursorType out of the result column. 
    param.value.asStmt
  

template setLob*(param : ptr dpiLob, value : Option[seq[byte]] , rownum : int = 0) =
  # use: int dpiVar_setFromLob(dpiVar *var, uint32_t pos, dpiLob *lob)
  discard

template getLob*(param : ptr dpiLob ) : Option[seq[byte]]  =
  discard
