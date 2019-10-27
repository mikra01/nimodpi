template copyString2DpiData(src : string, dest: ptr dpiData) =
  ## copy template into odpi-domain.
  ## the nimstring is copied into the dpiData struct
  var s = src
  copyMem(dest.value.asBytes.ptr,addr(s[0]), s.len)
  dest.value.asBytes.length = s.len.uint32
 
template copySeq2Data(src : seq[byte], dest: ptr dpiData) =
  ## copy template into odpi-domain.
  ## the nim bytesequence is copied into the dpiData struct
  var s = src
  copyMem(dest.value.asBytes.ptr,addr(s[0]),s.len)
  dest.value.asBytes.length = s.len.uint32