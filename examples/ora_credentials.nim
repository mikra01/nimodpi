const
    oracleuser: string = "sys"
    pw: string = "<pwd>"
    connectionstr: string = """(DESCRIPTION = (ADDRESS = 
                             (PROTOCOL = TCP)
                             (HOST = localhost)  
                             (PORT = 1521))
                             (CONNECT_DATA =(SERVER = DEDICATED)
                             (SERVICE_NAME = XEPDB1 )
                            ))"""
    # if there is a local Oracle XE instance running, let this file unchanged