(*i camlp4deps: "grammar/grammar.cma" i*)

DECLARE PLUGIN "universe_comparator"

open Names
open Errors
open Pp
open Nameops
open Global

let split (str : string) : string list=
  let rec split_helper (parts : string list) (cur_start : int) (cur : int) : string list =
    if (cur < String.length str) then
      begin
	if String.get str cur = '.' then
	  split_helper (parts @ [(String.sub str cur_start (cur - cur_start))]) (cur+1) (cur+1)
	else
	  split_helper parts cur_start (cur+1)
      end
    else
      begin
	parts @ [(String.sub str cur_start (cur - cur_start))]
      end
  in
  split_helper [] 0 0

let last_rest (l : 'a list) : 'a * ('a list) =
  let rec last_rest_helper (tmp : 'a list) (r : 'a list) =
    match r with
    | [] -> invalid_arg ""
    | [x] -> (x, tmp)
    | h :: t -> last_rest_helper (tmp @ [h]) t
  in
  last_rest_helper [] l
    
let u_of_ulit ulit =
  let (last, rest) =
    last_rest (split ulit)
  in
  try
    let int_last =
      int_of_string last
    in
    Some (Univ.Level.make (DirPath.make (List.map Id.of_string rest)) int_last)
  with
    Failure _ -> None
	       
let u_of_id id =
  begin
    let names, _ =
      Universes.global_universe_names ()
    in
    try Idmap.find id names
    with Not_found ->
      user_err_loc (Loc.dummy_loc, "Constraint", str "Undeclared or invalid universe " ++ pr_id id)
  end

let comparator uid1 ord uid2 eq_res le_res lt_res inv_le_res inv_lt_res =
  match ord with
  | Some Univ.Lt ->
     begin
       match eq_res, le_res, lt_res, inv_le_res, inv_lt_res with
       | (true, _, _, _, _) -> Pp.msg_info (Pp.str ("Doesn't hold because: " ^ uid1 ^ " = " ^ uid2))
       | (_, _, true, _, _) -> Pp.msg_info (Pp.str ("Holds: " ^ uid1 ^ " < " ^ uid2))
       | (_, _, _, true, _) -> Pp.msg_info (Pp.str ("Doesn't hold because: " ^ uid1 ^ " >= " ^ uid2))
       | (_, _, _, _, true) -> Pp.msg_info (Pp.str ("Doesn't hold because: " ^ uid1 ^ " > " ^ uid2))
       | (false, _, false, false, false) -> Pp.msg_info (Pp.str ("Consistent with the theory: " ^ uid1 ^ " < " ^ uid2))
     end
  | Some Univ.Le ->
     begin
       match eq_res, le_res, lt_res, inv_le_res, inv_lt_res with
       | (true, _, _, _, _) -> Pp.msg_info (Pp.str ("Holds because: " ^ uid1 ^ " = " ^ uid2))
       | (_, true, _, _, _) -> Pp.msg_info (Pp.str ("Holds: " ^ uid1 ^ " <= " ^ uid2))
       | (_, _, true, _, _) -> Pp.msg_info (Pp.str ("Holds because: " ^ uid1 ^ " < " ^ uid2))
       | (_, _, _, _, true) -> Pp.msg_info (Pp.str ("Doesn't hold because: " ^ uid1 ^ " > " ^ uid2))
       | (false, false, false, _, false) -> Pp.msg_info (Pp.str ("Consistent with the theory: " ^ uid1 ^ " <= " ^ uid2))
     end
  | Some Univ.Eq ->
     begin
       match eq_res, le_res, lt_res, inv_le_res, inv_lt_res with
       | (true, _, _, _, _) -> Pp.msg_info (Pp.str ("Holds: " ^ uid1 ^ " = " ^ uid2))
       | (_, true, _, true, _) -> Pp.msg_info (Pp.str ("Holds because: " ^ uid1 ^ " <= " ^ uid2 ^ " and " ^ uid1 ^ " >= " ^ uid2))
       | (_, _, true, _, _) -> Pp.msg_info (Pp.str ("Doesn't Hold because: " ^ uid1 ^ " < " ^ uid2))
       | (_, _, _, _, true) -> Pp.msg_info (Pp.str ("Doesn't Hold because: " ^ uid1 ^ " > " ^ uid2))
       | (false, _, false, _, false) -> Pp.msg_info (Pp.str ("Consistent with the theory: " ^ uid1 ^ " = " ^ uid2))
     end
  | None ->
     begin
       match eq_res, le_res, lt_res, inv_le_res, inv_lt_res with
       | (true, _, _, _, _) -> Pp.msg_info (Pp.str ("Inferred relation: " ^ uid1 ^ " = " ^ uid2))
       | (_, true, _, true, _) -> Pp.msg_info (Pp.str ("Inferred relation: " ^ uid1 ^ " = " ^ uid2))
       | (_, true, false, _, _) -> Pp.msg_info (Pp.str ("Inferred relation: " ^ uid1 ^ " <= " ^ uid2))
       | (_, _, _, true, false) -> Pp.msg_info (Pp.str ("Inferred relation: " ^ uid1 ^ " >= " ^ uid2))
       | (_, _, true, _, _) -> Pp.msg_info (Pp.str ("Inferred relation: " ^ uid1 ^ " < " ^ uid2))
       | (_, _, _, _, true) -> Pp.msg_info (Pp.str ("Inferred relation: " ^ uid1 ^ " > " ^ uid2))
       | (false, false, false, false, false) -> Pp.msg_info (Pp.str (uid1 ^ " and " ^ uid2 ^ " are not related"))
     end
    
let compare_universes (uid1, ord, uid2) : unit =
  let uid_to_u uid =
    if uid = "Set" then
      begin
	Univ.Level.set
      end
    else
      begin
	if uid = "Prop" then
	  begin
	    Univ.Level.prop
	  end
	else
	  begin
	    try
	      u_of_id (Id.of_string uid)
	      with
		UserError _ as e ->
		begin
		  match u_of_ulit uid with
		  | Some u -> u
		  | None -> raise e
		end
	  end
      end
  in
  let u1 =
    uid_to_u uid1
  in
  let u2 =
    uid_to_u uid2
  in
  let univs =
    universes ()
  in
  let eq_res =
    Univ.check_constraint univs (u1, Univ.Eq, u2)
  in
  let le_res =
    Univ.check_constraint univs (u1, Univ.Le, u2)
  in
  let lt_res =
    Univ.check_constraint univs (u1, Univ.Lt, u2)
  in
  let inv_le_res =
    Univ.check_constraint univs (u2, Univ.Le, u1)
  in
  let inv_lt_res =
    Univ.check_constraint univs (u2, Univ.Lt, u1)
  in
  comparator uid1 ord uid2 eq_res le_res lt_res inv_le_res inv_lt_res
       
VERNAC COMMAND EXTEND Compare_Universes CLASSIFIED AS QUERY
| [ "Compare" "Universes" string(uid1) "<" string(uid2) ] -> [compare_universes (uid1, Some Univ.Lt, uid2) ]
| [ "Compare" "Universes" string(uid1) ">" string(uid2) ] -> [compare_universes (uid2, Some Univ.Lt, uid1) ]
| [ "Compare" "Universes" string(uid1) "=" string(uid2) ] -> [compare_universes (uid1, Some Univ.Eq, uid2) ]
| [ "Compare" "Universes" string(uid1) "<=" string(uid2) ] -> [compare_universes (uid1, Some Univ.Le, uid2) ]
| [ "Compare" "Universes" string(uid1) ">=" string(uid2) ] -> [compare_universes (uid2, Some Univ.Le, uid1) ]
| [ "Compare" "Universes" string(uid1) "?" string(uid2) ] -> [compare_universes (uid1, None, uid2) ]
END