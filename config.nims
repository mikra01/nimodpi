import ospaths, strutils

task odpic_demo, "run odpi-c demo":
  withDir thisDir():
    switch("run")
    switch("app","console")
    setCommand "c", "demo/demo.nim"

task oracle_demo, "run db_oracle API examples (with ddl)":
  withDir thisDir():
    switch("run")
    switch("app","console")
    setCommand "c", "src/db_oracle.nim"