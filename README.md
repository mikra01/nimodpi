# nimodpi
Oracle ODPI-C wrapper for Nim

## [Oracle ODPI-C Documentation](https://oracle.github.io/odpi/)
 
### dependencies
- Oracle Instant Client (see ODPI-C Documentation for details)
- [nimterop](https://github.com/nimterop/nimterop) 

### how to install
clone this project directly or use "nimble install nimodpi".
then import the module "db_oracle" within your project. 
the dependent ODPI-C source is directly included into your project (via nimterop) 

See the "isMainModule" section at the end of the module for some examples.

Besides the abstraction layer you can also consume the raw ODPI-C API if something is
missing ( or PR me your solution ).

See /demo/demo.nim for some direct ODPI-C examples. 
The subdir /demo also contains an example how sqlplus could be utilised for script execution.

### Remarks
upgraded to Nim Compiler Version 1.2.6, ODPI-C 4.0.2 and nimterop 0.6.11. The ODPI-C version
is within the static section of nimodpi.nim (nimterop control file)
The NIM-API could be subject of change.

### Oracle XE installation
For testing just install a local copy of the oracle xe:
https://www.oracle.com/database/technologies/appdev/xe.html

The oracle instant client is already included.

Tests only against windows 10 OS - if you face problems while installing xe onto
your machine: the installer logs everything under the program files directory within the subdirectory
/Oracle/Inventory/logs. Before installing make sure a third party virus scanner is disabled.
(I faced no problems with the windows defender).

My database was created with the nls_character set "AL32UTF8"

To check your database characterset you could query for:

```PLSQL
select DECODE(parameter, 'NLS_CHARACTERSET', 'CHARACTER SET',
'NLS_LANGUAGE', 'LANGUAGE',
'NLS_TERRITORY', 'TERRITORY') name,
value from v$nls_parameters
WHERE parameter IN ( 'NLS_CHARACTERSET', 'NLS_LANGUAGE', 'NLS_TERRITORY')
/
```

If you like to browse the schemas use Oracle SQL Developer for instance.
Future examples will be based on the HR schema. 
This user is locked by default so the examples will only work if you use
sysdba for the connecting user.

### demo
before running the demo, adjust  "/demo/democredentials.nim" (login and connection_string) 
for the database you like to connect to. No ddl is executed. 

run the raw ODPI-C demo with "nimble demo".

run the nim demo with "nimble db_oracle".
this demo executes some DDL and performs a cleanup.

### Todo
direct bindings almost completed except SODA; 
the nimish abstraction layer (db_oracle) is functional but more examples needed.
next steps would be provide documented examples and cleanup of some quirks.

Comments, bug reports and PR´s appreciated.
