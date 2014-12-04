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

#define STACKSIZE 100

class parseritem{
   protected:
      unsigned numb;
		UNCH     * intstr;
	public:
		parseritem(unsigned nmb, UNCH * str);
		~parseritem();
		unsigned ItemNo(){return numb;}
		UNCH *   IntStr(){return intstr;}
		virtual UNCH *   DisplayPosition() = 0;
} ;

class scanner {
	public:
		scanner(){};
		virtual parseritem * getitem() = 0;
} ;

struct narray {
	unsigned num[3000]; // number doesn't really matter!
	};

class parser {
   private:
      scanner     * scnptr;
		parseritem  * LhdItem, * CurItem;
      unsigned    State, OpNo;
      unsigned    Stack[STACKSIZE], StackPntr;
		narray      * StateData, * StatePntr;
		unsigned    NumbStatePtrs, NumbStateDatas;
   public:
		parser(unsigned StateDataRes, unsigned StatePntrRec, scanner *&sptr);
      ~parser();
      void startparser();
		unsigned doparse(parseritem *& item);
		virtual void displayerror(parseritem * item) = 0;
} ;
