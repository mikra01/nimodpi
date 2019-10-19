template fetchBoolean*(val : ptr dpiData) : Option[bool] =
    ## fetches the specified value as boolean. the value is copied
    if val.isDbNull:
      none(bool)
    else:
      some(val.value.asBoolean)
  
template setBoolean*(param : ptr dpiData, value : Option[bool] ) =
    ## bind parameter setter boolean type.
    if value.isNone:
       param.setDbNull
    else: 
       param.setNotDbNull  
       param.value.asBoolean = value.get 
    
# simple type conversion templates.
template fetchFloat*(val : ptr dpiData) : Option[float32] =
    ## fetches the specified value as float. the value is copied 
    if val.isDbNull:
      none(float32)
    else:
      some(val.value.asFloat.float32)
  
proc setFloat*( param : ptr dpiData, value : Option[float32]) =
    ## bind parameter setter float32 type. 
    ## TODO: eval why template is not compiling
    if value.isNone: 
      param.setDbNull
    else:
      param.setNotDbNull  
      param.value.asFloat = value.get
  
template fetchDouble*(val : ptr dpiData) : Option[float64] =
    ## fetches the specified value as double (Nims 64 bit type). the value is copied 
    if val.isDbNull:
      none(float64)
    else:
      some(val.value.asDouble.float64)
  
proc setDouble*(param : ptr dpiData, value : Option[float64]) =
    ## bind parameter setter float64 type. 
    ## TODO: eval why template is not compiling
    if value.isNone:
      param.setDbNull
    else:  
      param.setNotDbNull
      param.value.asDouble = value.get   
    
template fetchUInt64*(val : ptr dpiData) : Option[uint64] =
    ## fetches the specified value as double (Nims 64 bit type). the value is copied 
    if val.isDbNull:
      none(uint64)
    else:
      some(val.value.asUint64)
  
template setUInt64*(param : ptr dpiData, value : Option[uint64]) =
    ## bind parameter setter uint64 type. 
    if value.isNone:
      param.setDbNull
    else:
      param.setNotDbNull  
      param.value.asUint64 = value.get
        
template fetchInt64*(val : ptr dpiData) : Option[int64] =
    ## fetches the specified value as double (Nims 64 bit type). the value is copied 
    if val.isDbNull:
      none(int64)
    else:
      some(val.value.asInt64)
  
proc setInt64( param : ptr dpiData, value : Option[int64]) =
     ## bind parameter setter int64 type. 
     if value.isNone:
       param.setDbNull
     else:  
       param.setNotDbNull
       param.value.asInt64  = value.get   
  
template fetchIntervalDS*(val : ptr dpiData ) : Option[Duration] =
    # todo: implement
    if val.isDbNull:
      none(Duration)
    else:
      some(val.toIntervalDs)
     
  
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
    
template fetchDateTime*( val : ptr dpiData ) : Option[DateTime] =
    ## fetches the specified value as DateTime. the value is copied 
    if val.isDbNull:
      none(DateTime)
    else:
      some(toDateTime(val))
  
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
    
template fetchString*( val : ptr dpiData ) : Option[string] =
    ## fetches the specified value as string. the value is copied  
    if val.isDbNull:
      none(string)
    else:
      some(toNimString(val))
  
template setString*(param : ParamTypeRef , rownum : int, value : Option[string] ) = 
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
  
template setBytes*(param : ParamTypeRef , rownum : int, value: Option[seq[byte]] ) = 
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
  
template fetchRefCursor*(param : ptr dpiData ) : ptr dpiStmt =
    ## fetches a refCursorType out of the result column. at the moment only the
    ## raw ODPI-C API could be used to consume the ref cursor.
    param.value.asStmt
  