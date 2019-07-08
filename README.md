# nimodpi
Oracle ODPI-C wrapper for Nim

## [Oracle ODPI-C Documentation](https://oracle.github.io/odpi/)
 
### dependencies
- Oracle Instant Client (see ODPI-C Documentation for details)
- nimterop 

### how to install
just import "nimodpi" within your project. See /demo/demo.nim for an example.
The subdir /demo also contains an example how sqlplus could be utilised for script execution.

at the moment only static linking supported.
nimterop downloads the ODPI-C sourcecode into subdirectory /build, 
processes it and injects the dependencies within the nimcache directory.

### demo
run the demo with "nimble demo".

before running, adjust  "/demo/democredentials.nim" (login and connection_string) 
for the database you like to connect to. No ddl is executed. 

### Todo
direct bindings almost completed except SODA; a nimish abstraction layer missing (WIP)

Comments, bug reports and PR´s appreciated.
