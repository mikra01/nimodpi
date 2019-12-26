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

Besides the abstraction layer you can also consume the raw API if something is
missing ( or PR me your solution ).

See /demo/demo.nim for some direct ODPI-C examples. 
The subdir /demo also contains an example how sqlplus could be utilised for script execution.

### Remarks
I tested the impl. only for the IA64 architecture with
nim-compiler version 1.0.2. 
The API could be subject of change.

### Oracle XE installation
For testing just install a local copy of the oracle xe:
https://www.oracle.com/database/technologies/appdev/xe.html

The oracle instant client is already included.

I tested it only for the windows 10 OS - if you face problems while installing xe onto
your machine the installer logs everything under the program files directory within the subdirectory
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

If you like to browse the schemas use Oracle SQL Developer.
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

Update(Dec. 2019): I've implemented typed objects and nested tables(unpublished at the moment). In January 2019 I will do some rework of the API to get seamless integration with these object types (blob's included). The Nim target version will be 1.0.4.

Comments, bug reports and PR´s appreciated.
