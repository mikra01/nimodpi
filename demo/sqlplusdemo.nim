import ../nimodpi
import os
import osproc
import streams

#[
very basic example to get a script within the current working
directory executed. only 10lines are consumed. 
sqlplus must be accessible from the path-env. 

the script performs a "select 1 from dual "
]#

var sqlplusProc  = startProcess("sqlplus user/pw@host:port/servicename ","",[],nil,{poEvalCommand,poUsePath})
# insert your credentials here
sqlplusProc.inputStream.writeLine("@demoscript.sql")
sqlplusProc.inputStream.flush()

var line = ""

for i in countup(0,10):
  discard sqlplusProc.outputStream.readLine(line.TaintedString)
  echo line

sqlplusProc.inputStream.writeLine(" exit ")
sqlplusProc.inputStream.writeLine("/")
sqlplusProc.inputStream.flush()

for i in countup(0,10):
  discard sqlplusProc.outputStream.readLine(line.TaintedString)
  echo line

sqlplusProc.close()
