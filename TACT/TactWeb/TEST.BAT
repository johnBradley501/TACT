rem
rem     This Batch file runs TACTWEB software which does most of
rem     the work to generate results.         ... john bradley
rem
set tactpath=c:\tact\tactweb
set tactpage=page/page.column
\jpi\vid tactweb -i - -f c:\website\cgi-dos\tactweb\midsumme.tdb test.htm <content.in
