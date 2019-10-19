# Package
version = "0.1.0"
author = "Michael Krauter"
description = " oracle odpi-c wrapper "
license = "MIT"
skipDirs = @["demo"]

# Dependencies
requires "nim >= 0.19.6"
requires "nimterop >= 0.1.0"


task demo, "running demo":
  exec "nim odpic_demo"

task db_oracle, "running db_oracle examples ":
  exec "nim oracle_demo"

