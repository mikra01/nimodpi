# nimodpi
Oracle ODPI-C wrapper for Nim

## [ODPI-C Documentation](https://oracle.github.io/odpi/)
 
### dependencies
nimterop 

### how to install
just import "nimodpi" within your project. 

at the moment only static linking supported.
nimterop downloads the ODPI-C sourcecode into subdirectory /build, 
processes it and injects the dependencies within the nimcache directory.

### demo
run the demo with "nimble demo".

before running, adjust  "/demo/democredentials.nim" (login and connection_string) 
for the database you like to connect to. No ddl is executed. 

### Todo
direct bindings completed; a nimish abstraction layer missing (WIP)

Comments, bug reports and PR´s appreciated.
