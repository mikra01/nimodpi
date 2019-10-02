# dpi2nimtype conversion helper

proc toDateTime(p: ptr dpiTimestamp): DateTime =
  ## dpiTimestamp to DateTime
  let utcoffset: int = p.tzHourOffset*3600.int + p.tzMinuteOffset*60
  proc utcTzInfo(time: Time): ZonedTime =
    ZonedTime(utcOffset: utcoffset, isDst: false, time: time)
  initDateTime(p.day, Month(p.month), p.year, p.hour, p.minute, p.second,
      p.fsecond,
    newTimezone("Etc/UTC", utcTzInfo, utcTzInfo))

template toNimString*(data: ptr dpiData): string =
  ## copy template into nim domain
  var result: string = newString(data.value.asBytes.length)
  copyMem(addr(result[0]), data.value.asBytes.ptr, result.len)
  result

template toNimByteSeq*(data: ptr dpiData): seq[byte] =
  ## copy template for binary data into nim domain
  var result: seq[byte] = newSeq[byte](data.value.asBytes.length)
  copyMem(addr(result[0]), data.value.asBytes.ptr, result.len)
  result
