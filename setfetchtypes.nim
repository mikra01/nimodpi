template fetchBoolean*(val : ptr dpiData) : Option[bool] =
    ## fetches the specified value as boolean. the value is copied
    if val.isDbNull:
      none(bool)
    else:
      some(val.value.asBoolean)

template fetchBoolean*(param : ParamTypeRef) : Option[bool] =
  ## fetches the sepcified value as boolean. suitable for
  ## non-array bind parameters
  param[0].fetchBoolean

template setBoolean*(param : ptr dpiData, value : Option[bool] ) =
    ## bind parameter setter boolean type.
    if value.isNone:
       param.setDbNull
    else: 
       param.setNotDbNull  
       param.value.asBoolean = value.get 

template setBoolean*( param : ParamTypeRef, value : Option[bool]) =
  ## access template for single bind variables
  param[0].setBoolean(value)      
      
# simple type conversion templates.
template fetchFloat*(val : ptr dpiData) : Option[float32] =
    ## fetches the specified value as float. the value is copied 
    if val.isDbNull:
      none(float32)
    else:
      some(val.value.asFloat.float32)
  
template fetchFloat*( param : ParamTypeRef) : Option[float32] =
  param[0].fetchFloat

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

template fetchDouble*(val : ptr dpiData) : Option[float64] =
    ## fetches the specified value as double (Nims 64 bit type). the value is copied 
    if val.isDbNull:
      none(float64)
    else:
      some(val.value.asDouble.float64)

template fetchDouble*( param : ParamTypeRef ) : Option[float64] =
  param[0].fetchDouble  

proc setDouble*(param : ptr dpiData, value : Option[float64]) =
    ## bind parameter setter float64 type. 
    ## TODO: eval why template is not compiling
    if value.isNone:
      param.setDbNull
    else:  
      param.setNotDbNull
      param.value.asDouble = value.get   

template fetchDouble*( param : ParamTypeRef ) : Option[float64] =
  param[0].fetchDouble

template fetchUInt64*(val : ptr dpiData) : Option[uint64] =
    ## fetches the specified value as double (Nims 64 bit type). the value is copied 
    if val.isDbNull:
      none(uint64)
    else:
      some(val.value.asUint64)

template fetchUInt64*( param : ParamTypeRef ) : Option[uint64] =
  param[0].fetchUInt64

template setUInt64*(param : ptr dpiData, value : Option[uint64]) =
    ## bind parameter setter uint64 type. 
    if value.isNone:
      param.setDbNull
    else:
      param.setNotDbNull  
      param.value.asUint64 = value.get

template setUInt64*( param : ParamTypeRef, value : Option[uint64] ) =
  param[0].setUInt64(value)

template fetchInt64*(val : ptr dpiData) : Option[int64] =
    ## fetches the specified value as double (Nims 64 bit type). the value is copied 
    if val.isDbNull:
      none(int64)
    else:
      some(val.value.asInt64)

template fetchInt64*( param : ParamTypeRef ) : Option[int64] =
  param[0].fetchInt64

proc setInt64( param : ptr dpiData, value : Option[int64]) =
     ## bind parameter setter int64 type. 
     if value.isNone:
       param.setDbNull
     else:  
       param.setNotDbNull
       param.value.asInt64  = value.get   

template setInt64( param : ParamTypeRef, value :  Option[int64] )  =
  param[0].setInt64(value)

template fetchIntervalDS*(val : ptr dpiData ) : Option[Duration] =
    # todo: implement
    if val.isDbNull:
      none(Duration)
    else:
      some(val.toIntervalDs)

template fetchIntervalDS*(param : ParamTypeRef) : Option[Duration] =
  param[0].fetchIntervalDS     
  
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

template fetchDateTime*( val : ptr dpiData ) : Option[DateTime] =
    ## fetches the specified value as DateTime. the value is copied 
    if val.isDbNull:
      none(DateTime)
    else:
      some(toDateTime(val))
  
template fetchDateTime*( param: ParamTypeRef) : Option[DateTime] =
  param[0].fetchDateTime

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

template fetchString*( val : ptr dpiData ) : Option[string] =
    ## fetches the specified value as string. the value is copied  
    if val.isDbNull:
      none(string)
    else:
      some(toNimString(val))
  
template fetchString*( param : ParamTypeRef) : Option[string] =
  param[0].fetchString

template setString*(param : ParamTypeRef , rownum : int, value : Option[string]) = 
    ## bind parameter setter string type. for single parameters set the rownum
    ## to 0. 
    if value.isNone:
      param.buffer.setDbNull
    else: 
      param.buffer.setNotDbNull 
      let str : cstring  = $value.get
      discard dpiVar_setFromBytes(param.paramVar,
                                  rownum.uint32,
                                  str,
                                  str.len.uint32)    

template fetchBytes*( val : ptr dpiData ) : Option[seq[byte]] =
    ## fetches the specified value as seq[byte]. the byte array is copied
    if val.isDbNull:
      none(seq[byte])
    else:
      some(toNimByteSeq(val))

template fetchBytes*( param : ParamTypeRef ) : Option[seq[byte]] =
  param[0].fetchBytes

template setBytes*(param : ParamTypeRef , rownum : int = 0, value: Option[seq[byte]]) = 
    ## bind parameter setter seq[byte] type. this setter operates always with index 0
    ## the value is copied into the drivers domain 
    if value.isNone:
      param.buffer.setDbNull
    else:
      param.buffer.setNotDbNull  
      let seqb : seq[byte] = value.get
      let cstr = cast[cstring](unsafeAddr(seqb[0]))
      discard dpiVar_setFromBytes(param.paramVar,
                                  rownum.uint32,
                                  cstr,
                                  seqb.len.uint32)    
    
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
  discard

template getLob*(param : ptr dpiLob ) : Option[seq[byte]]  =
  discard
