// copyright (c) 1996 John Bradley

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

//----------------------------------------------------------------------
// A note about code conventions within a string:
//   0C - end of string code
//   1C - word separator in a string
//   2C - extra code separator
// 377C - highest char to build delimiter high key
//----------------------------------------------------------------------

#define NONRETDIACCODE 254
#define WORDSEPCODE 1
#define EXTRACODESEP 2

#define NULLCHAR 0
#define LETTER 1
#define RETDIAC 2
#define NONRETDIAC 3
// intermediate values: IgnBrkStart, IgnBrkEnd, IgnBrkStEnd, RefBrkStart,
//					      	 RefBrkEnd, RefBrkStEnd,
#define CONTINUATIONCHAR 10
// intermediate values: LabelStart, LabelEnd, LabelStEnd, BYUStart, Counter,
#define HIGHKEYCHAR 16

#define HIGHKEYCODE 255
#define WORDSEPCODE 1


extern UNCH SimpAlphTable[256];
extern UNCH TypeOfChar[255]; // starting index is 1
#define TOC(N) (TypeOfChar[N-1])
extern unsigned SortNoBitsPerChar;

void BuildAlphabetXlate(LineCollection *&Alphabet, LineCollection *&RetDiac,
							  LineCollection *&NonRetD, LineCollection *&ContChar,
							  LineCollection *&SepChar);

void IntToFullWord(UNCH *iword, UNCH *fword);

void FullToSortWord(UNCH *sword, UNCH *fword);

void SortToFullWord(UNCH *fword, UNCH *sword);

void IntToSortWord(UNCH *iword, UNCH *sword);

unsigned int IntToNextSortWord(UNCH *iword, UNCH *sword,
						  UNCH *pre=0, UNCH *post=0, UNCH *replace=0);
						  //pre, post are in "full" format, replace is in sort format

unsigned int FindNextSortWord(UNCH *itxt);

void SortToIntWord(UNCH *sword, UNCH *iword);
