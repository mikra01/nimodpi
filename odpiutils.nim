# utils dedicated to the nim odpi wrapper

proc `$`* (p: var dpiErrorInfo): string =
  ## get  the string representation of dpiErrorInfo
  var s = newString(p.messageLength)
  var fnName = newString(p.fnName.len)
  if s.len > 0:
    copyMem(addr(s[0]), p.message, s.len)
  if fnName.len > 0:
    copyMem(addr(fnName[0]), p.fnName, fnName.len)

  "dpiErrorInfo: code:" & $p.code & " " & s & " (" & fnName & ")"




