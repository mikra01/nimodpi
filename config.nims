import ospaths, strutils

task odpic_demo, "run odpi-c demo":
  withDir thisDir():
    switch("run")
    setCommand "c", "demo/demo.nim"