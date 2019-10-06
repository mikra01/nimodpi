# dpi2nimtype conversion helper

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
  let d = data.value.asBytes
  var result: string = newString(d.length)
  copyMem(addr(result[0]), d.ptr, result.len)
  result

template toNimByteSeq(data: ptr dpiData): seq[byte] =
  ## copy template for binary data into nim domain
  let d = data.value.asBytes
  var result: seq[byte] = newSeq[byte](d.length)
  copyMem(addr(result[0]), d.ptr, result.len)
  result
