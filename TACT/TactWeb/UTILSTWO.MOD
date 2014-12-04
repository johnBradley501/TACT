IMPLEMENTATION MODULE UtilsTwo ;
(* copyright (c) 1989-96 John Bradley, Lidio Presutti, University of Toronto *)

(* Licensed under the Apache License, Version 2.0 (the "License");             *)
(* you may not use this file except in compliance with the License.            *)
(* You may obtain a copy of the License at                                     *)
(* http://www.apache.org/licenses/LICENSE-2.0                                  *)
(*                                                                             *)
(* Unless required by applicable law or agreed to in writing, software         *)
(* distributed under the License is distributed on an "AS IS" BASIS,           *)
(* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.    *)
(* See the License for the specific language governing permissions and         *)
(* limitations under the License.                                              *)

(*V1=Dbg Debugging code *)

IMPORT Str;
FROM Utils IMPORT BOpen,BFile,FindFileInList, RWType;
FROM GlobalDefs IMPORT StrAny;
FROM ResCollection IMPORT ResCollectionType;
FROM ResDataArray IMPORT
  (* proc *) GetDataArray, GetNextDataArrayStringItem;
FROM ResCollection IMPORT
   (* proc *) ReleaseCollection;
FROM ResMessages IMPORT
   (*proc*) MsgString, MsgCard, MsgInt, GetResMessage,
            PutResError, PutResWarning, PutResMessage;

TYPE
    MonthNms = ARRAY [1..12] OF ARRAY [0..15] OF CHAR;

VAR
    MonthName: MonthNms; 
    MonthNamesGot:  BOOLEAN;

PROCEDURE MakePrintableDate(day, month, year: CARDINAL;
                        VAR String:   ARRAY OF CHAR);
VAR  ResC:  ResCollectionType;
     i:     CARDINAL;
     dummy: BOOLEAN;

(*RES OLD DTA 0
January February March April May June July August September
October November December
*)
BEGIN
   IF NOT MonthNamesGot THEN
      MonthNamesGot := TRUE;
      GetDataArray( (*RES REM INS*) 0, ResC);
      FOR i := 1 TO 12 DO
          dummy := GetNextDataArrayStringItem(ResC,MonthName[i])
      END;
      ReleaseCollection(ResC);
   END;
(*RES OLD MSG 26
%0 %1, %3
*)
   MsgString(MonthName[month],0);
   MsgCard(day,0);
   MsgCard(month,0);
   MsgCard(year,0);
   GetResMessage( (*RES REM INS*) 26, String);
END MakePrintableDate;


PROCEDURE IOErrorMessage ( ErrorNo : CARDINAL ;
                     VAR Message:  ARRAY OF CHAR);

VAR
    ResNo:     CARDINAL;
    TempStr:   StrAny;
    Res:       StrAny;
    TempOK:    BOOLEAN ;
BEGIN
  CASE ErrorNo OF
    0 :
       Message[0] := 0C;   (* m.s. - OK *)
       RETURN |
       (*RES OLD MSG 0
       M2 FileIO Internal Error.
       *)
    1 :    ResNo := (*RES REM INS*) 0 |
       (*RES OLD MSG 1
       The File was not Found.
       *)
    2 :      ResNo := (*RES REM INS*) 1 |
       (*RES OLD MSG 3
       The Path was not Found.
       *)
    3 :      ResNo := (*RES REM INS*) 3 |
       (*RES OLD MSG 4
       There are Too Many Files Open at Once.
       *)
    4 :      ResNo := (*RES REM INS*) 4 |
       (*RES OLD MSG 7
       File Access is Denied.
       *)
    5 :  ResNo := (*RES REM INS*) 7 |
      (*RES OLD MSG 9
      Invalid File Handle.
      *)
    6 : ResNo := (*RES REM INS*) 9 |
      (*RES OLD MSG 460
      The Memory Control Blocks are Destroyed.
      *)
    7 : ResNo := (*RES REM INS*) 460  |
      (*RES OLD MSG 10
      There is Insufficient Memory for IO.
      *)
    8 : ResNo := (*RES REM INS*) 10 |
      (*RES OLD MSG 461
      There is an Invalid Memory-block Address.
      *)
    9 : ResNo := (*RES REM INS*) 461  |
      (*RES OLD MSG 462
      You have Specified an Invalid Disk Drive.
      *)
    15: ResNo := (*RES REM INS*) 462  |
      (*RES OLD MSG 463
      You have Tried to Access a Write-protected Disk.
      *)
    19: ResNo := (*RES REM INS*) 463  |
      (*RES OLD MSG 464
      The Drive is not Ready.
      *)
    21: ResNo := (*RES REM INS*) 464  |
      (*RES OLD MSG 465
      Data Error Based on Cyclic Redundancy Check (CRC).
      *)
    23: ResNo := (*RES REM INS*) 465  |
      (*RES OLD MSG 466
      There is a Disk Drive Seek Error.
      *)
    25: ResNo := (*RES REM INS*) 466  |
      (*RES OLD MSG 467
      A Non-MS-DOS Disk has been Detected.
      *)
    26: ResNo := (*RES REM INS*) 467  |
      (*RES OLD MSG 468
      A Sector has not been Found on the Disk.
      *)
    27: ResNo := (*RES REM INS*) 468  |
      (*RES OLD MSG 469
      The Printer is Out of Paper.
      *)
    28: ResNo := (*RES REM INS*) 469  |
      (*RES OLD MSG 470
      A Write Fault Error has been Detected.
      *)
    29: ResNo := (*RES REM INS*) 470  |
      (*RES OLD MSG 471
      A Read Fault Error has been Detected.
      *)
    30: ResNo := (*RES REM INS*) 471  |
      (*RES OLD MSG 472
      A General Failure has been Detected.
      *)
    31: ResNo := (*RES REM INS*) 472  |
       (*RES OLD MSG 2
       The File Already Exists.
       *)
    80:      ResNo := (*RES REM INS*) 2 |
      (*RES OLD MSG 473
      A Critical Failure on Interrupt 24H has been Detected.
      *)
    83: ResNo := (*RES REM INS*) 473  |
      (*RES OLD MSG 474
      The Disk is Full (Write Failed).
      *)
    0F0H:ResNo := (*RES REM INS*) 474  | (* JPI internal *)
 ELSE
      (*RES OLD MSG 23
      An Unknown IO Error has Occurred.
      *)
      ResNo := (*RES REM INS*) 23
 END;
 GetResMessage( ResNo, Message) ;
   (*RES OLD MSG 91
   DOS Reports:
   *)
 GetResMessage( (*RES REM INS*) 91 , TempStr ) ;
 Str.Append( TempStr, '  (');
 Str.CardToStr( LONGCARD( ErrorNo ), Res, 16, TempOK ) ;
 Str.Append( TempStr, Res ) ;
 Str.Append( TempStr, 'H)  ' ) ;
 Str.Concat(Message, TempStr,Message);


(*  m.s. - derived from Lib.WrDosError   | 1  : ResNo := ADR('Invalid function number');
    | 2  : ResNo := ADR('File not found');
    | 3  : ResNo := ADR('Path not found');
    | 4  : ResNo := ADR('Too many open files (no handles left)');
    | 5  : ResNo := ADR('Access denied');
    | 6  : ResNo := ADR('Invalid handle');
    | 7  : ResNo := ADR('Memory control blocks destroyed');
    | 8  : ResNo := ADR('Insufficient memory');
    | 9  : ResNo := ADR('Invalid memory block address');
    | 10 : ResNo := ADR('Invalid environment');
    | 11 : ResNo := ADR('Invalid format');
    | 12 : ResNo := ADR('Invalid access code');
    | 13 : ResNo := ADR('Invalid data');
    (*14 : Reserved *)
    | 15 : ResNo := ADR('Invalid drive was specified');
    | 16 : ResNo := ADR('Attempt to remove the current directory');
    | 17 : ResNo := ADR('Not same device');
    | 18 : ResNo := ADR('No more files');
    | 19 : ResNo := ADR('Attempt to write on write-protected diskette');
    | 20 : ResNo := ADR('Unknown unit');
    | 21 : ResNo := ADR('Drive not ready');
    | 22 : ResNo := ADR('Unknown command');
    | 23 : ResNo := ADR('Data error (CRC)');
    | 24 : ResNo := ADR('Bad request structure length');
    | 25 : ResNo := ADR('Seek error');
    | 26 : ResNo := ADR('Unknown media type');
    | 27 : ResNo := ADR('Sector not found');
    | 28 : ResNo := ADR('Printer out of paper');
    | 29 : ResNo := ADR('Write fault');
    | 30 : ResNo := ADR('Read fault');
    | 31 : ResNo := ADR('General failure');
    | 32 : ResNo := ADR('Sharing Violation');
    | 33 : ResNo := ADR('Lock Violation');
    | 34 : ResNo := ADR('Invalid disk change');
    | 35 : ResNo := ADR('FCB unavailable');
    (*36..79 : Reserved *)
    | 80 : ResNo := ADR('File exists');
    (*81 : Reserved *)
    | 82 : ResNo := ADR('Cannot Make');
    | 83 : ResNo := ADR('Fail on INT 24');
    | 0F0H:ResNo := ADR('Disk Full (write failed)'); (* JPI internal *)
  ELSE
      WriteErrorString(ADR('Unknown DOS Error : '));
      Str.CardToStr(LONGCARD(ErrorNo), Temp, 4, OK);
      WriteErrorString(ADR(Temp));
  END ;
  WriteErrorString(ResNo);
  WriteErrorString(ADR(Ln));
*)
END IOErrorMessage ;

(*  m.s. - old version that used BResultType
PROCEDURE IOErrorMessage(Code:     CARDINAL;
                     VAR Message:  ARRAY OF CHAR);
VAR
    ResNo:     CARDINAL;
    TempStr:   StrAny;
BEGIN
   CASE Code OF
    OK :
       Message[0] := 0C;
       RETURN |


(*RES OLD MSG 5
The Disk is Full.
*)
    DeviceFull:        ResNo := (*RES REM INS*) 5 |

(*RES OLD MSG 6
The Directory is Full.
*)
    DirectoryFull:     ResNo := (*RES REM INS*) 6 |


(*RES OLD MSG 8
Device Access is Denied.
*)
    DeviceAccessDenied:ResNo := (*RES REM INS*) 8 |

(*RES OLD MSG 11
There is no such Device.
*)
    NoSuchDevice:      ResNo := (*RES REM INS*) 11 |

(*RES OLD MSG 12
The Device is not Ready.
*)
    DeviceNotReady:    ResNo := (*RES REM INS*) 12 |

(*RES OLD MSG 13
End of Medium.
*)
    EndOfMedium:       ResNo := (*RES REM INS*) 13 |

(*RES OLD MSG 14
Data Error.
*)
    DataError:         ResNo := (*RES REM INS*) 14 |

(*RES OLD MSG 15
The Device Failed.
*)
    DeviceFailure:     ResNo := (*RES REM INS*) 15 |

(*  The following messages are not used in this version: here
    for documentation purposes only   j.b.:

(*RES OLD MSG 16
File Opening Failed.
*)
    OpenFailed:        ResNo := (*RES REM INS*) 16 |

(*RES OLD MSG 17
File Creation Failed.
*)
    CreateFailed:      ResNo := (*RES REM INS*) 17 |

(*RES OLD MSG 18
Writing to File Failed.
*)
    WriteFailed:       ResNo := (*RES REM INS*) 18 |

(*RES OLD MSG 19
File Closing Failed.
*)
    CloseFailed:       ResNo := (*RES REM INS*) 19 |

(*RES OLD MSG 20
Reading from File Failed.
*)
    ReadFailed:        ResNo := (*RES REM INS*) 20 |

*)

(*RES OLD MSG 21
There is Insufficient Data.
*)
    InsufficientData:  ResNo := (*RES REM INS*) 21 |

(*RES OLD MSG 22
An Error in Translation Occurred.
*)
    TranslationError:  ResNo := (*RES REM INS*) 22
   ELSE

(*RES OLD MSG 23
An Unknown IO Error Occurred.
*)
       ResNo := (*RES REM INS*) 23
   END;
   GetResMessage( ResNo, Message) ;
   (*RES OLD MSG 91
   DOS Reports:
   *)
   GetResMessage( (*RES REM INS*) 91 , TempStr ) ;
   Str.Append( TempStr, '  ');
   Str.Concat(Message, TempStr,Message);
END IOErrorMessage;
*)

PROCEDURE FindAndOpen(List:     ARRAY OF CHAR;
                      FName:    ARRAY OF CHAR;
                  VAR FileID:   BFile;
                  VAR ErrorMsg: ARRAY OF CHAR): BOOLEAN;
VAR
   DirName:        ARRAY[0..63] OF CHAR;
   FullFileName:   StrAny;
   BResult:        CARDINAL;
   TErrorMsg:      StrAny;
BEGIN
   IF NOT FindFileInList(List,FName,DirName) THEN

(*RES OLD MSG 24
File %0 was not Found.
*)
      MsgString(FName,0);
      GetResMessage( (*RES REM INS*) 24, ErrorMsg);
      RETURN FALSE
   END;
   Str.Concat(FullFileName,DirName,FName);
   BOpen(FileID,FullFileName,ReadType,BResult);
   IF BResult <> OK THEN

(*RES OLD MSG 25
File %0: %1
*)

      IOErrorMessage(BResult,TErrorMsg);
      MsgString(FName,0);
      MsgString(TErrorMsg,0);
      GetResMessage( (*RES REM INS*) 25, ErrorMsg);
      RETURN FALSE;
   END;
   ErrorMsg[0] := 0C;
   RETURN TRUE;
END FindAndOpen;

BEGIN
   MonthNamesGot := FALSE;

END UtilsTwo.
