const
  testTypesSql : cstring = """
select 'test ' as teststr, 
       to_number('-134.123456') as testnum, 
       hextoraw('C0FFEE') as rawcol,
       to_timestamp( '29.02.2012 13:01:0987654321', 'DD.MM.YYYY HH24:MI:SSFF8' ) as tstamp,
       to_number('-134.123456789012345678901234567') as testnum2 
       from dual
union all 
select 'test2' as teststr, 
        to_number('1.0123456789') as testnum, 
        hextoraw('ABCDEF') as rawcol, 
        null as tstamp,
        to_number('1234567890123456789012345678901234567') as testnum2       
        from dual
"""

  testRefCursor : cstring = """
begin 
 open :1 for select 'X' StrVal from dual union all select 'Y' from dual; 
end;
"""
