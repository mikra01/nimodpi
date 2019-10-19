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
       param.asBoolean.value = value.some  
    
# simple type conversion templates.
template fetchFloat*(val : ptr dpiData) : Option[float32] =
    ## fetches the specified value as float. the value is copied 
    if val.isDbNull:
      none(float32)
    else:
      some(val.value.asFloat.float32)
  
template setFloat*( param : ptr dpiData, value : Option[float32]) =
    ## bind parameter setter float32 type. 
    if value.isNone: 
      param.setDbNull
    else:
      param.setNotDbNull  
      param.asFloat.value = value.some
  
template fetchDouble*(val : ptr dpiData) : Option[float64] =
    ## fetches the specified value as double (Nims 64 bit type). the value is copied 
    if val.isDbNull:
      none(float64)
    else:
      some(val.value.asDouble.float64)
  
template setDouble*(param : ptr dpiData, value : Option[float64]) =
    ## bind parameter setter float64 type. 
    if value.isNone:
      param.setDbNull
    else:  
      param.setNotDbNull
      param.asDouble = value.some   
    
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
      param.asUint64 = value.some    
        
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
      param.value.asIntervalDS.fseconds = value.some.nanoseconds    
      param.value.asIntervalDS.seconds = value.some.seconds 
      param.value.asIntervalDS.minutes = value.some.minutes
      param.value.asIntervalDS.hours = value.some.hours
      param.value.asIntervalDS.days = value.some.days
    
template fetchDateTime*( val : ptr dpiData ) : Option[DateTime] =
    ## fetches the specified value as DateTime. the value is copied 
    if val.isDbNull:
      none(DateTime)
    else:
      some(toDateTime(val))
  
template setDateTime*(param : ptr dpiData , value : Option[DateTime] ) = 
    ## bind parameter setter DateTime type. this setter operates always with index 1
    if value.isNone:
      param.setDbNull
    else:
      param.setNotDbNull  
      let dt = cast[DateTime](some)
      let utcoffset = dt.utcOffset
      param.value.asTimestamp.year = dt.year
      param.value.asTimestamp.month = dt.month     
      param.value.asTimestamp.day = dt.day
      param.value.asTimestamp.hour = dt.hour
      param.value.asTimestamp.minute = dt.minute
      param.value.asTimestamp.second =  dt.second
      param.value.asTimestamp.fsecond = dt.nanosecond
      
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
  