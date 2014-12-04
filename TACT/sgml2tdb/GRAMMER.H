// copyright (c) 1995 John Bradley

/* Licensed under the Apache License, Version 2.0 (the "License");             */
/* you may not use this file except in compliance with the License.            */
/* You may obtain a copy of the License at                                     */
/* http://www.apache.org/licenses/LICENSE-2.0                                  */
/*                                                                             */
/* Unless required by applicable law or agreed to in writing, software         */
/* distributed under the License is distributed on an "AS IS" BASIS,           */
/* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.    */
/* See the License for the specific language governing permissions and         */
/* limitations under the License.                                              */

/* File Produced by LALR Version 5.01: May 30, 1996 */
/* 14 <tactid type ::=> */
#define 	TACTIDTYPESTR1 14
/* 16 <tactid type ::=> LINENO */
#define TACTIDTYPELINE 16
/* 17 <tactid type ::=> WORD */
#define 	TACTIDTYPEWORD 17
/* 18 <standard types ::=> STRING */
#define 	TACTIDTYPESTR2 18
/* 19 <standard types ::=> NUMBER */
#define 	TACTIDTYPENUMB 19
/* 22 <main name ::=> <name> */
#define TACTIDMAINNAME 22
/* 23 <alt name list ::=> <alt name list> , <name> */
#define TACTIDALTNAME1 23
/* 24 <alt name list ::=> <name> */
#define 	TACTIDALTNAME2 24
/* 29 <declare type ::=> */
#define 	VARTYPESTR1 29
/* 31 <declare name ::=> <name> */
#define 	DECLAREDGLOBALNAME 31
/* 35 <segment type ::=> OPEN */
#define SEGMENTISOPEN 35
/* 36 <segment type ::=> CLOSE */
#define SEGMENTISCLOSE 36
/* 37 <element list ::=> <element name> */
#define FIRSTELEMENTNAME 37
/* 38 <element list ::=> <element list> , <element name> */
#define OTHERELEMENTNAMES 38
/* 40 <actions ::=> <actions> <action statement> */
#define 	ACTIONSTATEMENT1 40
/* 41 <actions ::=> <action statement> */
#define 	ACTIONSTATEMENT2 41
/* 47 <simple action statement ::=> error <char expression> */
#define 	 HANDLEERRORCOMMAND 47
/* 48 <simple action statement ::=> remark <char expression> */
#define HANDLEREMARKCOMMAND 48
/* 52 <change value statements ::=> inc <declared name> */
#define 	 HANDLEINC 52
/* 53 <change value statements ::=> dec <declared name> */
#define 	 HANDLEDEC 53
/* 55 <popstack which ::=> POP */
#define 	  ITSPOP 55
/* 56 <popstack which ::=> STACK */
#define 	  ITSSTACK 56
/* 59 <ps item ::=> <var name> */
#define POPSTACKVAR 59
/* 62 <output item ::=> <char expression> */
#define 	 HANDLEOUTPUTCOMMAND 62
/* 63 <output item ::=> blines <arith expression> */
#define DOBLANKLINES 63
/* 66 <word op ::=> collect <logical expression> */
#define 	 HANDLECOLLECTCOMMAND 66
/* 67 <word op ::=> append <char expression> */
#define 	 HANDLEAPPENDCOMMAND 67
/* 68 <word op ::=> prepend <char expression> */
#define 	 HANDLEPREPENDCOMMAND 68
/* 69 <word op ::=> replace <char expression> */
#define HANDLEREPLACECOMMAND 69
/* 72 <format option ::=> compress <logical expression> */
#define 	 SETFORMATCOMPRESS 72
/* 73 <format option ::=> centre <logical expression> */
#define 	 SETFORMATCENTRE 73
/* 74 <format option ::=> display <logical expression> */
#define 	 SETFORMATDISPLAY 74
/* 75 <format option ::=> fill <logical expression> */
#define 	 SETFORMATFILL 75
/* 76 <format option ::=> fold <arith expression> */
#define 	 SETFORMATFOLD 76
/* 77 <format option ::=> indent <arith expression> */
#define 	 SETFORMATINDENT 77
/* 78 <format option ::=> to <var name> */
#define 	 SETOUTTOVAR 78
/* 79 <format option ::=> to tdb */
#define 	 SETOUTTOTDB 79
/* 80 <let statement ::=> <destination> = <let expression> */
#define 	 DOTHEASSIGN 80
/* 81 <destination ::=> <var name> */
#define 	 GETASSIGNID 81
/* 83 <char expression ::=> <char expression> | <char item> */
#define 	CHAREXPAPPEND 83
/* 85 <char item ::=> <string> */
#define 	CHAREXPSTRING 85
/* 86 <char item ::=> nl */
#define 	CHAREXPNEWLINE 86
/* 87 <char item ::=> THISGI */
#define CHARTHISGI 87
/* 89 <char item ::=> SUBSTR ( <sub operands> ) */
#define 	CHARSUBSTR 89
/* 90 <char item ::=> PAD ( <pad operands> ) */
#define CHARPAD 90
/* 91 <char item ::=> UPPER ( <char expression> ) */
#define 	CHAREXPUPPER 91
/* 93 <sub operands ::=> <sub item> , <start numb> */
#define 	SUBSTRMISSLEN 93
/* 94 <sub item ::=> <char expression> */
#define 	SUBSTRITEM 94
/* 95 <start numb ::=> <arith expression> */
#define 	SUBSTRSTART 95
/* 96 <len numb ::=> <arith expression> */
#define 	SUBSTRLEN 96
/* 98 <pad item ::=> <char expression> */
#define 	PADITEM 98
/* 99 <pad length ::=> <arith expression> */
#define 	PADLEN 99
/* 100 <pad pattern ::=> */
#define 	PADNOPATTERN 100
/* 101 <pad pattern ::=> , <char expression> */
#define 	PADPATTERN 101
/* 102 <pad position ::=> */
#define 	PADBACK1 102
/* 103 <pad position ::=> FRONT , */
#define 	PADFRONT 103
/* 104 <pad position ::=> BACK , */
#define 	PADBACK2 104
/* 107 <arith expression ::=> <arith expression> + <arith term> */
#define 	 ARITHEXPPLUS 107
/* 108 <arith expression ::=> <arith expression> - <arith term> */
#define 	 ARITHEXPMINUS 108
/* 110 <signed term ::=> - <arith term> */
#define 	 ARITHEXPUMINUS 110
/* 113 <arith term ::=> <arith term> * <arith primary> */
#define 	 ARITHEXPTIMES 113
/* 114 <arith term ::=> <arith term> / <arith primary> */
#define 	 ARITHEXPDIV 114
/* 117 <arith item ::=> <number> */
#define 	 ARITHEXPNUMB 117
/* 121 <arith item ::=> FIND ( <char expression> , <char expression> ) */
#define ARITHEXPFIND 121
/* 122 <arith item ::=> MAX ( <arith expression> , <arith expression> ) */
#define 	 ARITHEXPMAX 122
/* 123 <arith item ::=> MIN ( <arith expression> , <arith expression> ) */
#define 	 ARITHEXPMIN 123
/* 124 <arith item ::=> INDEX ( <char expression> , <char expression> ) */
#define 	 ARITHEXPINDEX 124
/* 125 <arith item ::=> LENGTH ( <char expression> ) */
#define 	 ARITHEXPLEN 125
/* 126 <name or attrib ::=> <var name> */
#define 	 GETTACTGLOBAL 126
/* 128 <attribute ::=> @ <name> */
#define 	 LOADLOCALATTRIB 128
/* 129 <attribute ::=> <the element> @ <name> */
#define 	 LOADELEMATTRIB 129
/* 130 <the element ::=> <element name> */
#define SAVEELEMENT 130
/* 134 <if start ::=> IF <logical expression> THEN <statement end> */
#define 	 IFSTART 134
/* 138 <elsif line ::=> <elsif id> <logical expression> THEN <statement end> */
#define ELSEIFCOND 138
/* 139 <elsif id ::=> ELSE IF */
#define ELSEIFSTART 139
/* 142 <ELSE ID ::=> ELSE <statement end> */
#define 	 IFELSESTART 142
/* 143 <end if ::=> END <statement end> */
#define 	 IFEND 143
/* 145 <while test ::=> <WHILE ID> <logical expression> <statement end> */
#define 	 WHILECOND 145
/* 146 <WHILE ID ::=> WHILE */
#define 	 WHILESTART 146
/* 147 <end while ::=> END <statement end> */
#define 	 WHILEEND 147
/* 149 <logical expression ::=> <logical expression> OR <logical term> */
#define 	LOGOR 149
/* 151 <logical term ::=> <logical term> AND <signed logical term> */
#define 	LOGAND 151
/* 153 <signed logical term ::=> NOT <logical primary> */
#define LOGNOT 153
/* 157 <logical primary ::=> ON */
#define 	 LOGEXPON 157
/* 158 <logical primary ::=> OFF */
#define LOGEXPOFF 158
/* 159 <compare ::=> <exp 1> = <exp 2> */
#define 	 COMPEQU 159
/* 160 <compare ::=> <exp 1> ~ = <exp 2> */
#define 	 COMPNOTEQU 160
/* 161 <compare ::=> <exp 1> "> <exp 2> */
#define 	 COMPGT 161
/* 162 <compare ::=> <exp 1> "< <exp 2> */
#define 	 COMPLT 162
/* 163 <compare ::=> <exp 1> "> = <exp 2> */
#define 	 COMPGE 163
/* 164 <compare ::=> <exp 1> "< = <exp 2> */
#define 	 COMPLE 164
/* 169 <in funct elem ::=> <element name> */
#define DOINFUNCT 169
/* 170 <is funct elem ::=> <element name> */
#define DOISFUNCT 170
/* 174 <declared name ::=> <var name> */
#define DECLAREDISTACTID 174
#define DECLAREDISVAR 174
