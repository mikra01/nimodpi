# pipelined table function example 
# app access via package logic (decoupled tables)
import db_oracle
import options,times

# table_function example
# intended to run with a local oracle instance (XE)
# if you like to access a remote instance adjust user,pw 
# and connection string
include ora_credentials

var 
    hr_pa_employee_spec : SqlQuery = osql""" 
CREATE OR REPLACE PACKAGE hr.pa_employee AS
    TYPE ty_employee_rec IS RECORD (
        employee_id          NUMBER(6, 0),
        first_name           VARCHAR2(20 BYTE),
        last_name            VARCHAR2(25 BYTE),
        email                VARCHAR2(25 BYTE),
        phone_number         VARCHAR2(20 BYTE),
        hire_date            DATE,
        job_id               VARCHAR2(10 BYTE),
        job_title            VARCHAR2(35 BYTE),
        manager_id           NUMBER(6, 0),
        manager_first_name   VARCHAR2(20 BYTE),
        manager_last_name    VARCHAR2(25 BYTE)
    );
    TYPE ty_employees IS
        TABLE OF ty_employee_rec;
    FUNCTION getemployeesby_department_id (
        department_id_in NUMBER
    ) RETURN ty_employees
        PIPELINED;
END pa_employee;
    """
    hr_pa_employee_body : SqlQuery = osql"""
CREATE OR REPLACE PACKAGE BODY hr.pa_employee AS
    FUNCTION getemployeesby_department_id (
        department_id_in NUMBER
    ) RETURN ty_employees
        PIPELINED
    AS
        va_ret ty_employees;
        
        CURSOR employee_cur IS
        SELECT /* hr.pa_employee.getemployeesby_department_id */
            emp.employee_id,
            emp.first_name,
            emp.last_name,
            emp.email,
            emp.phone_number,
            emp.hire_date,
            j.job_id,
            j.job_title,
            man.employee_id   AS manager_id,
            man.first_name    AS manager_first_name,
            man.last_name     AS manager_last_name
        FROM
            hr.employees   emp
            INNER JOIN hr.jobs        j ON ( j.job_id = emp.job_id )
            LEFT JOIN hr.employees   man ON ( man.employee_id = emp.manager_id )
        WHERE
            emp.department_id = department_id_in;

    BEGIN
        OPEN employee_cur;
        LOOP
            FETCH employee_cur BULK COLLECT INTO va_ret LIMIT 100;
            EXIT WHEN va_ret.count = 0;
            FOR indx IN 1..va_ret.count LOOP PIPE ROW ( va_ret(indx) );
            END LOOP;
        END LOOP;

        CLOSE employee_cur;
    END getemployeesby_department_id;

END pa_employee;
    """
    octx: OracleContext

type
    EmployeeDbRec = object 
        employee_id : Option[int] 
        first_name : Option[string]           
        last_name : Option[string]            
        email : Option[string]                
        phone_number : Option[string]         
        hire_date : Option[DateTime] 
        job_id  : Option[string]            
        job_title : Option[string]           
        manager_id : Option[int]          
        manager_first_name : Option[string]  
        manager_last_name : Option[string]   

newOracleContext(octx,DpiAuthMode.SYSDBA)
# create the context with authentication Method
# SYSDBA and default encoding (UTF8)
var conn: OracleConnection

createConnection(octx, connectionstr, oracleuser, pw, conn)
# create the connection with the desired server, 
# credentials and the context

conn.executeDDL(hr_pa_employee_spec)
conn.executeDDL(hr_pa_employee_body)  
echo "package hr.pa_employee created"

var getEmpSql : SqlQuery = osql"""SELECT
    employee_id,
    first_name,
    last_name,
    email,
    phone_number,
    hire_date,
    job_id,
    job_title,
    manager_id,
    manager_first_name,
    manager_last_name
FROM
    TABLE ( hr.pa_employee.getemployeesby_department_id( :department_id) )
 """

var pstmt : PreparedStatement
conn.newPreparedStatement(getEmpSql , pstmt, 5)
# create prepared statement for the specified query and
# the number of buffered result-rows. the number of buffered
# rows (window) is fixed and can't changed later on

withPreparedStatement(pstmt):
  # use withPreparedStatement to recycle it automatically
  # after leaving this block. 
  var rs: ResultSet
  var param = addBindParameter(pstmt,Int64ColumnTypeParam,"department_id")
  # example: bind by name

  param.setInt64(some(80.int64))
  # create and set the bind parameter. query bind
  # parameter are always non-columnar. 

  executeStatement(pstmt,rs)
    # execute the statement. if the resulting rows
    # fit into entire window we are done here.
 
  for row in rs.resultSetRowIterator:
      # the result iterator fetches internally further
      # rows if present 
      # example of value retrieval by columnname or index
      # the column of the row is accessed by colnum or name
      echo $row["EMPLOYEE_ID"].fetchInt64 &
      " " & $row["FIRST_NAME"].fetchString &
      " " & $row["LAST_NAME"].fetchString &
      " " & $row["EMAIL"].fetchString &
      " " & $row["PHONE_NUMBER"].fetchString &
      " " & row["HIRE_DATE"].fetchDateTime.get.format("yyyy-MM-dd") & 
      " " & $row["JOB_ID"].fetchInt64 &  
      " " & $row["JOB_TITLE"].fetchString &
      " " & $row["MANAGER_ID"].fetchInt64 &    
      " " & $row["MANAGER_FIRST_NAME"].fetchString &
      " " & $row["MANAGER_LAST_NAME"].fetchString  
      # columns can be accessed by column-index or column_name

var hr_pa_employee_drop : SqlQuery = osql"""drop package hr.pa_employee"""
# conn.executeDDL(hr_pa_employee_drop)
echo "package hr.pa_employee dropped"

conn.releaseConnection
destroyOracleContext(octx)  
