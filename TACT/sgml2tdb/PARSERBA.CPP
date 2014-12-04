// copyright (c) 1994 John Bradley

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

#include "config.h"
#include "tools.h"
#include "resource.h"
#include "parserba.h"
//This is a kludge:   j.b.
#define PNE int
#include "sgmlfnsm.h"
#include "sgmlaux.h"
#include <alloc.h>

	extern resfile *ResFile;

parseritem::parseritem(unsigned nmb, UNCH * str)
		{numb = nmb; intstr = savestr(str);}

parseritem::~parseritem(){frem((UNIV)intstr);}

parser::parser(unsigned StateDataRes, unsigned StatePntrRes, scanner *&sptr)
{
	scnptr = sptr;
	StatePntr = (narray *) ResFile->GetResNA(StatePntrRes, NumbStatePtrs);
	StateData = (narray *) ResFile->GetResNA(StateDataRes, NumbStateDatas);
	LhdItem = 0;
	CurItem = 0;
   State = 1;
	OpNo = 1;
   StackPntr = 0;
}

parser::~parser()
{
	free(StateData);
	free(StatePntr);
	if (CurItem != 0)delete CurItem;
	if (LhdItem != 0)delete LhdItem;
}

void parser::startparser()
{
	if (CurItem != 0)delete CurItem;
	LhdItem = scnptr->getitem();
	State = 1;
	OpNo = 1;
	StackPntr = 0;
/* CurItem.IntStr := ''; */
}

#define PUSH 1
#define IFITEM 2
#define OUTPUT 3
#define LOOKAHEAD 4
#define POP 5
#define IFTOP 6
#define GOTO 7
#define SYNTAXERROR 0

unsigned parser::doparse(parseritem *& item)
{
	BOOLEAN looping;
   while(1){
	  switch (StateData->num[OpNo-1]) {
	  case PUSH:
		  if(++StackPntr > STACKSIZE) exit(2);
		  Stack[StackPntr-1] = StateData->num[OpNo];
		  OpNo += 2;
		  break;
	  case IFITEM:
		  if (CurItem != 0) delete CurItem;
		  CurItem = LhdItem;
		  LhdItem = scnptr->getitem();
		  looping = TRUE;
		  while ((StateData->num[OpNo-1] == 2) && looping) {
			 if (StateData->num[OpNo] == CurItem->ItemNo()) {
				State = StateData->num[OpNo+1];
				OpNo = StatePntr->num[State-1];
				looping = FALSE;}
			 else OpNo += 3;
        }
		  break;
	 case OUTPUT:
		  item = CurItem;
		  OpNo += 2;
		  return StateData->num[OpNo-2];
	 case LOOKAHEAD:
        OpNo++;
		  while((StateData->num[OpNo-1] != 0) && (StateData->num[OpNo-1] != LhdItem->ItemNo()))
				 OpNo++;
		  if (StateData->num[OpNo-1] == 0) OpNo += 2;
        else {
          OpNo++;
			 while(StateData->num[OpNo-1] != 0) OpNo++;
			 State = StateData->num[OpNo];
			 OpNo = StatePntr->num[State-1];}
		  break;
    case POP:
		  StackPntr -= StateData->num[OpNo];
        OpNo += 2;
        break;
    case IFTOP:
		  if(Stack[StackPntr-1] == StateData->num[OpNo]) {
			 State = StateData->num[OpNo+1];
			 OpNo = StatePntr->num[State-1]; }
		  else OpNo += 3;
		  break;
    case GOTO:
		  State = StateData->num[OpNo];
		  OpNo = StatePntr->num[State-1];
		  break;
	case SYNTAXERROR:
		  if (CurItem->ItemNo() == 0)CurItem = LhdItem;
		  displayerror(CurItem);
		  /*RES OLD MSG 161
        I couldn't understand this!  Problem occurred at :"%0"

        MsgString(CurItem.IntStr,0);
		  PutResError( (*RES REM INS*) 161 ); */
		  item = CurItem;
		  return 10000 ;
	  default: // Invalid StateTable Op
		  exit(100);
		 // ProgramErrorAndHalt('Invalid StateTable Op found in Parser');
	  } // switch StateData
	} /* while(1) */
}
