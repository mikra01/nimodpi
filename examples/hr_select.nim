import db_oracle
import options

# example: table select
# intended to run with a local oracle instance (XE)
# if you like to access a remote instance adjust user,pw 
# and connection string
include ora_credentials

var octx: OracleContext

newOracleContext(octx,DpiAuthMode.SYSDBA)
# create the context with authentication Method
# SYSDBA and default encoding (UTF8)
var conn: OracleConnection

createConnection(octx, connectionstr, oracleuser, pw, conn)
# create the connection with the desired server, 
# credentials and the context

var query2: SqlQuery = osql""" select 
          rowid,
          EMPLOYEE_ID, 
          FIRST_NAME, 
          LAST_NAME, 
          EMAIL, 
          PHONE_NUMBER, 
          HIRE_DATE, 
          JOB_ID, 
          SALARY, 
          COMMISSION_PCT, 
          MANAGER_ID, 
          DEPARTMENT_ID 
    from hr.employees where department_id = :param1  """

var pstmt: PreparedStatement

newPreparedStatement(conn, query2, pstmt, 10)
# create prepared statement for the specified query and
# the number of buffered result-rows. the number of buffered
# rows (window) is fixed and can't changed later on

withPreparedStatement(pstmt):
  # use withPreparedStatement to recycle it automatically
  # after leaving this block. 
  var rs: ResultSet
  var param = addBindParameter(pstmt,Int64ColumnTypeParam,"param1")
  # example: bind by name

  param.setInt64(some(80.int64))
  # create and set the bind parameter. query bind
  # parameter are always non-columnar. 

  executeStatement(pstmt,rs)
    # execute the statement. if the resulting rows
    # fit into entire window we are done here.
 
  for i,ct in rs.resultColumnTypeIterator:
    # consume columnTypes of the resultSet
    echo "cname:" & rs.rsColumnNames[i] & " colnumidx: " & 
      $(i+1) & " " & $ct

  for row in rs.resultSetRowIterator:
      # the result iterator fetches internally further
      # rows if present 
      # example of value retrieval by columnname or index
      # the column of the row is accessed by colnum or name
      echo $row[0].fetchRowId &
      " " & $row[1].fetchDouble &
      " " & $row["FIRST_NAME"].fetchString &
      " " & $row["LAST_NAME"].fetchString &
      " " & $row[10].fetchInt64 &
      " " & $row[11].fetchInt64 
      # columns can be accessed by column-index or column_name

  conn.releaseConnection
  destroyOracleContext(octx)      