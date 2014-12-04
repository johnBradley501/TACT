rem
rem     This Batch file runs TACTWEB software which does most of
rem     the work to generate results.         ... john bradley
rem
set REQUEST_METHOD=GET
set QUERY_STRING=Qb.*&display_type:WORD
set tactpath=c:\tact\tactweb
set tactpage=page/page.column
erase test2.htm
rem \jpi\vid tactweb c:\website\cgi-dos\tactweb\midsumme.tdb test2.htm
tactweb c:\website\cgi-dos\tactweb\midsumme.tdb test2.htm
