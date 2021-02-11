template setString2DpiData(src : Option[string], dest: ptr dpiData) =
  ## sets the pointer to the nimstring into odpi-domain.
  # buffer created with newVar provide a ptr to the buffer area
  copyMem(dest.value.asBytes.ptr,unsafeAddr(src.get[0]),src.get.len) 
  dest.value.asBytes.length = src.get.len.uint32

 
template setSeq2DpiData(src : Option[seq[byte]], dest: ptr dpiData) =
  ## sets the pointer to the nim sequence into odpi-domain.
  copyMem(dest.value.asBytes.ptr,unsafeAddr(src.get[0]), src.get.len) 
  dest.value.asBytes.length = src.get.len.uint32
  