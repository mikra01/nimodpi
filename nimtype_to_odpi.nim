template copyString2DpiData(src : var string, dest: ptr dpiData) =
  ## copy template into odpi-domain.
  ## the nimstring is copied into the dpiData structs dbBytes 
  ## pointer. this memory area is provided by odpi-c (exception: dbiObjectType? )
  ## invoke only for dpi_vars - for all other targets use: dpiData_setBytes
  copyMem(dest.value.asBytes.ptr,addr(src[0]), src.len) 
  dest.value.asBytes.length = src.len.uint32
 
template copySeq2Data(src : var seq[byte], dest: ptr dpiData) =
  ## copy template into odpi-domain.
  ## the nim bytesequence is copied into the dbBytes 
  ## pointer. this memory area is provided by odpi-c (exception: dbiObjectType)
  copyMem(dest.value.asBytes.ptr,addr(src[0]), src.len) 
  dest.value.asBytes.length = src.len.uint32
  