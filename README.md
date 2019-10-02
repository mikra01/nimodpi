# nimodpi
Oracle ODPI-C wrapper for Nim

## [Oracle ODPI-C Documentation](https://oracle.github.io/odpi/)
 
### dependencies
- Oracle Instant Client (see ODPI-C Documentation for details)
- nimterop 

### how to install
just import "nimodpi" within your project. See /demo/demo.nim for an example. This
is the original ODPI-C API. 
The subdir /demo also contains an example how sqlplus could be utilised for script execution.

ODPI-C is directly included into your project.
nimterop downloads the ODPI-C sourcecode into subdirectory /build, 
processes it and injects the dependencies within the nimcache directory.

The high-level nim API is in db_oracle (nimodpi will be automatically included).
At the moment only selects without parameter binding possible. An example how to use
it is at the end of the file.


### Remarks
I tested it only for the IA64 architecture.

### Oracle XE installation
For testing you could install a local copy of the oracle xe installation:
https://www.oracle.com/database/technologies/appdev/xe.html

The oracle instant client is already included.

I tested it only for the windows 10 OS - if you face problems while installing
the installer logs everything under the program files directory within the subdirectory
/Oracle/Inventory/logs. Before installing make sure a third party virus scanner is disabled.
(I faced no problems with the windows defender).

My database was created with the nls_character set "AL32UTF8"

To check your database you could query for:

```PLSQL
select DECODE(parameter, 'NLS_CHARACTERSET', 'CHARACTER SET',
'NLS_LANGUAGE', 'LANGUAGE',
'NLS_TERRITORY', 'TERRITORY') name,
value from v$nls_parameters
WHERE parameter IN ( 'NLS_CHARACTERSET', 'NLS_LANGUAGE', 'NLS_TERRITORY')
/
```

If you like to browse the schemas use Oracle SQL Developer.
Future examples will be based on the HR schema. 
This user is locked by default so the examples will only work if you use
sysdba for the connecting user.

### demo
run the demo with "nimble demo".

before running, adjust  "/demo/democredentials.nim" (login and connection_string) 
for the database you like to connect to. No ddl is executed. 

### Todo
direct bindings almost completed except SODA; a nimish abstraction layer is WIP (see db_oracle.nim)

Comments, bug reports and PR´s appreciated.
