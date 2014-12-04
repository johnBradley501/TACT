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

const unsigned THISTDBVERSION=5;
const unsigned THISPDBVERSION=6;
const unsigned THISCORVERSION=5;
const unsigned HYPERLENGTH=1024;
const unsigned HYPERLENGTHM1=HYPERLENGTH - 1;
const unsigned HNODATAPTRS=510; // HyperLength / TSIZE(INTEGER) - TSIZE(CARDINAL)
const unsigned HNOPDBWORDS=511;
const unsigned HNOTOKENS=169; // HyperLength / TSIZE(HTokenData)
const unsigned BASEHTYPELEN=3; // 2 + 1 [0C for  Word]
const unsigned MAXDBTITLELENGTH=42; // Maximum number of characters in DB Title
const unsigned MAXNOLOGDATA=254; // (HyperLength - TSIZE(LONGCARD)) / TSIZE(HLogDataType)
const unsigned TYPEMAXDATAPOS=(HYPERLENGTH - 2 * 2);
	 // leave room for Prev + NextHRec pointers

#define REFDELIMID '$'


void PackStr(UNCH *in, UNCH *out, unsigned short nbits=7);
void UnpackStr(UNCH *in, UNCH *out, unsigned short bits=7);
int PackedStrCompare(UNCH *a, UNCH *b);
/* Returns:	 0  if two packed strings are equal
		-1  if Str "a" is less than Str "b"
		 1  if Str "a" is greater than Str "b"		*/

void HuffEncode( UNCH *in, UNCH *out, unsigned inl, unsigned &outl);
void HuffDecode(UNCH *in, UNCH *out, unsigned outl);


enum HyperRType { HHeader, CorHeader, Htext, HLogList, HTypeList, HTokenList,
				HDataPntr, PDBData};

struct TDBString {
	unsigned long TotalWords;
	UNCH          TDBStr[256];
};

inline int TDBStrCompare( TDBString *a, TDBString *b )
	{return PackedStrCompare(a->TDBStr, b->TDBStr);};

struct TDBTypeData {
	unsigned    NoOccur;
	UNCH        PackedWord[256];
	};

inline int TDBTypeCompare( TDBTypeData *a, TDBTypeData *b )
	{return PackedStrCompare(a->PackedWord, b->PackedWord);};

//	 TDBTypePntr = POINTER TO TDBTypeData ;

struct HTypeData {
	unsigned NoOccur;
	UNCH     Word[256]; // zero-terminated
	};

//  HTypePntr = POINTER TO HTypeData ;

struct HOccurData {
	unsigned TRecNo;
	UNCH     TRecPos; // used as a 1-byte number
	};

struct HTokenData {
	unsigned HRecNo;  // pointer to headword (type)
	UNCH     HRecPos;
	unsigned TRecNo;  // pointer to text
	unsigned TRecPos;
	unsigned LRecNo;  // pointer to log area
	UNCH     LRecPos;
	};

struct HCompTokenData {
	unsigned HRecNo;
	UNCH     HRecPos;
	unsigned TOffset;
	UNCH     LOffset;
	};

struct HLogData {
	signed char   StructID;
	UNCH TokenNoOffset;
	union {
		struct {
			UNCH   SRecPos;
			UNCH   SRecNo;
			} shr;
		unsigned   Count;
		};
	};

struct TactidNameData {
	int      id;
	UNCH     pref;
	UNCH     name[256];
};

struct TDBRefStringData {
  int  ID;
  UNCH SRec;    // Start position offset
  UNCH SPos;
  UNCH ERec;    // End position
  UNCH EPos;
  };

struct RefStringData {
  int            ID;
  unsigned       SRec;    // actual DB Start position
  UNCH           SPos;
  UNCH           ERec;    // end position
  UNCH           EPos;
  };

/*	 (* allow a max of 170 = 1024 DIV SIZE(TDBRefStringData) = 1024 DIV 6 strings *)
	 TDBRefStrRecList     = ARRAY[1..170] OF TDBRefStringData;
	 TDBRefStrRecListPntr = POINTER TO TDBRefStrRecList;
	 RefStrRecList        = ARRAY[1..170] OF RefStringData;
	 RefStrRecListPntr    = POINTER TO RefStrRecList;   */


class HRecPntr {
public:
	unsigned Rec, Idx; };

extern HRecPntr NilHRP;

class TDBHeaderType{
public:
	UNCH               TDBID[4];
	UNCH               Title[MAXDBTITLELENGTH];
	unsigned           TDBVersion, Year, Month, Day,
							 BeginType;
	HRecPntr           EndType;
	unsigned           NoTypes, BeginStr, EndStr, BeginStrRec, NoStrRecs,
							 BeginLog, EndLog, BeginToken, BeginText;
	HRecPntr           EndText, EndToken;
	// unsigned           dummy; //Makebase reserves 88 bytes j.b.
};

union	HyperData {
	UNCH             TextData[HYPERLENGTH];         // HText
	TDBHeaderType    TDBHeader;                     // HHeader
	struct {                                        // HLogList
		unsigned long   BaseTokenNo;
		HLogData        LogData[MAXNOLOGDATA+1];
		} ld;
	struct {                                        // HTypeList
/* Overlay TypeData with DataPntr for easy of common code access
	value range 0..170 = (1024-1) DIV (pntr+NoOccurs+Word+0C) = 1023 DIV (2+2+1+1) */
		unsigned     typeFiller[510];
		unsigned     PrevHRec;
		unsigned     NextHRec;
		} tyd;
	struct {                                        // HDataPntr
		unsigned     NoDataPtrsUsed;
		unsigned     DataPntr[HNODATAPTRS+1];
		} dad;
	struct {                                        // HTokenList
		HRecPntr     BaseText, BaseLog;
//		unsigned     BaseTextRec, BaseTextPos,
//						 BaseLogRec,  BaseLogPos;
		HCompTokenData TokenData[HNOTOKENS];
		} tod;
	struct {
		unsigned     FirstFree;
		unsigned     PDBCardinal[HNOPDBWORDS];
	} pdbd;
};

#define PASTHEADER (sizeof(TDBHeaderType))
	// PASTHEADER will be 88
#define OCCURRECSIZE (sizeof(HOccurData))
	// will be 3
#define HNOOCCURS ((TYPEMAXDATAPOS - 2) / OCCURRECSIZE)
	//	(* 339 (was 341) *)
#define MAXSPACEFOROCCURSINREC (HNOOCCURS * OCCURRECSIZE)
	// (* = 1017 (was 1023) *)

extern UNCH TDBIDModel[4];
extern UNCH PDBIDModel[4];


class hfile {
private:
	FILE      *hfile;
	UNCH      *pname;
	HRecPntr  pos;
//	unsigned  TPtrLen;
	int		 TPtrLen;
	int       TDataPos;
	HyperData data;
	TDBHeaderType hdr;

	void WriteRec();
public:
	hfile(UNCH *name);
	HRecPntr AppendSpn(void *dta, unsigned sze); /* will split data between records */
	HRecPntr Append(void *dta, unsigned sze); /* will  not split data between records */
   void AppendChar(char c);
	unsigned FinishSection(); // returns start of >next< page
	TDBHeaderType *Header(){return &hdr;}
	HyperData *Data(){return &data;}
	HRecPntr CurrentPos(){return pos;}

	int InitPtrData();
	HRecPntr AddPtrData(void *inp, unsigned l);
	HRecPntr FinishPtrData();

	HRecPntr AddToken( HRecPntr hwrd, HRecPntr text, HRecPntr logp);

	void InitTypes();
	HRecPntr AddType(HTypeData &Data);
	void AddOccur( HRecPntr d);
	HRecPntr hfile::FinishTypes();
	
	void FinishTDB();
} ;

extern hfile *TDBFile;

void StartTDBFile(UNCH *fname, LineCollection *&title, LineCollection *&reftemp);
