# dpi2nimtype conversion helper
# pointer types (strings) are copied into nim domain
template  toDateTime(p: ptr dpiData): DateTime =
  ## dpiTimestamp to DateTime
  let dpits = p.value.asTimestamp
  let utcoffset: int = dpits.tzHourOffset*3600.int + dpits.tzMinuteOffset*60
  
  proc utcTzInfo(time: Time): ZonedTime =
    ZonedTime(utcOffset: utcoffset, isDst: false, time: time)
  initDateTime(dpits.day, Month(dpits.month), dpits.year, 
              dpits.hour, dpits.minute, dpits.second,dpits.fsecond,
              newTimezone("Etc/UTC", utcTzInfo, utcTzInfo))

template toNimString(data: ptr dpiData): string =
  ## copy template into nim domain
  var result = newString(data.value.asBytes.length)
  copyMem(addr(result[0]), data.value.asBytes.ptr, result.len)
  result

template toNimByteSeq(data: ptr dpiData): seq[byte] =
  ## copy template for binary data into nim domain
  var result = newSeq[byte](data.value.asBytes.length)
  copyMem(addr(result[0]), data.value.asBytes.ptr, result.len)
  result

template toIntervalDs(data : ptr dpiData) : Duration =
  initDuration(nanoseconds = data.value.asIntervalDS.fseconds,
               microseconds = 0,
               milliseconds = 0,
               seconds = data.value.asIntervalDS.seconds, 
               minutes = data.value.asIntervalDS.minutes, 
               hours = data.value.asIntervalDS.hours, 
               days = data.value.asIntervalDS.days , 
               weeks = 0)
  