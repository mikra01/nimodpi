const
  oracleuser : cstring = "scott"
  pw : cstring = "tiger"
  # credentials provided only for demo purpose.  
  connString : cstring = """(DESCRIPTION = (ADDRESS = 
                              (PROTOCOL = TCP)
                              (HOST = <hostname>  )  
                              (PORT = <port> ))
                              (CONNECT_DATA =(SERVER = DEDICATED)
                              (SERVICE_NAME = <service_name> )
                             ))"""
  # the connectionstring - tns_entry out of tnsnames.ora not tested
