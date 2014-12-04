IMPLEMENTATION MODULE MainLists;
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


FROM TACTListModule IMPORT DiscardList;
FROM PositionManagement IMPORT DiscardDisplayItem;
FROM MemTACTList IMPORT NewMemoryList;
FROM VirtMem IMPORT FreePool, ChangePoolNo;


PROCEDURE DiscardMainLists(Type: DiscardMainListType);
BEGIN
   DiscardDisplayItem(SelectedList,SelectedListPos);
   IF Type = DiscardAll THEN
	IF PosListStatus = PosMade THEN
	   DiscardDisplayItem(ListByPosition,PositionListPos);
	   PosListStatus := NoPos;
	END;
	IF ListByTypeMade THEN
	   DiscardDisplayItem(ListByType,TypeListPos);
	   ListByTypeMade := FALSE;
	END;

	FreePool( PoolNoForSelectLists ) ;
	DiscardList( SelectedList ) ;

	DiscardList(ListByPosition);
	DiscardList(ListByType);
	ListByPosition := NewMemoryList( PoolNoForSelectLists );
	ListByType := NewMemoryList( PoolNoForSelectLists );
   ELSE
	ChangePoolNo( PoolNoForSelectLists, PoolNoForOldSelect ) ;

	IF PosListStatus = PosMade THEN
	   DiscardDisplayItem(ListByPosition,PositionListPos);
	   DiscardList(ListByPosition);
	END;
	IF ListByTypeMade THEN
	   DiscardDisplayItem(ListByType,TypeListPos);
	   DiscardList(ListByType);
	END;

	(* avoid problems with DiscardList by making new memory list later here *)
	IF PosListStatus = PosMade THEN
	   ListByPosition := NewMemoryList( PoolNoForSelectLists );
	   PosListStatus := NoPos;
	END;
	IF ListByTypeMade THEN
	   ListByType := NewMemoryList( PoolNoForSelectLists );
	   ListByTypeMade := FALSE;
	END;
   END;
END DiscardMainLists;

BEGIN
   SelectedListEmpty := TRUE;
   ListByTypeMade := FALSE;
END MainLists.
