const
  oracleuser : cstring = "sys"
  pw : cstring = "<pwd>"
  # credentials provided only for demo purpose (working only for local oracl xe installation)  
  connString : cstring = """(DESCRIPTION = (ADDRESS = 
                              (PROTOCOL = TCP)
                              (HOST = localhost  )  
                              (PORT = 1521 ))
                              (CONNECT_DATA =(SERVER = DEDICATED)
                              (SERVICE_NAME = XEPDB1 )
                             ))"""
  # the connectionstring - tns_entry out of tnsnames.ora not tested
