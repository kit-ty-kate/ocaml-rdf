(*********************************************************************************)
(*                OCaml-RDF                                                      *)
(*                                                                               *)
(*    Copyright (C) 2012-2016 Institut National de Recherche en Informatique     *)
(*    et en Automatique. All rights reserved.                                    *)
(*                                                                               *)
(*    This program is free software; you can redistribute it and/or modify       *)
(*    it under the terms of the GNU Lesser General Public License version        *)
(*    3 as published by the Free Software Foundation.                            *)
(*                                                                               *)
(*    This program is distributed in the hope that it will be useful,            *)
(*    but WITHOUT ANY WARRANTY; without even the implied warranty of             *)
(*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *)
(*    GNU General Public License for more details.                               *)
(*                                                                               *)
(*    You should have received a copy of the GNU General Public License          *)
(*    along with this program; if not, write to the Free Software                *)
(*    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA                   *)
(*    02111-1307  USA                                                            *)
(*                                                                               *)
(*    Contact: Maxence.Guesdon@inria.fr                                          *)
(*                                                                               *)
(*********************************************************************************)

(** *)

let () = Random.self_init();;

type literal = {
    lit_value : string ;
    lit_language : string option ;
    lit_type : Iri.t option ;
  }
type blank_id = string

type term =
  | Iri of Iri.t
  | Literal of literal
  | Blank
  | Blank_ of blank_id

exception Invalid_date of string

let () = Printexc.register_printer
  (function
   | Invalid_date str -> Some (Printf.sprintf "Invalid date %s" str)
   | _ -> None
  )

type triple = term * Iri.t * term

type datetime =
  { stamp : Ptime.t ;
    tz: Ptime.tz_offset_s option ;
  }

let datetime_of_string str =
  match Ptime.of_rfc3339 str with
     Ok (stamp, tz, _) -> { stamp ; tz }
   | Error (`RFC3339 ((p1,p2), e)) ->
      let b = Buffer.create 256 in
      let fmt = Format.formatter_of_buffer b in
      Format.fprintf fmt "%s\n" str ;
      if p2 > p1 then
        Format.fprintf fmt "Characters %d-%d: " p1 p2
      else
        Format.fprintf fmt "Character %d: " p1;
      Ptime.pp_rfc3339_error fmt e;
      Format.pp_print_flush fmt () ;
      let err = Buffer.contents b in
      raise (Invalid_date err)

let string_of_datetime t = Ptime.to_rfc3339 ?tz_offset_s: t.tz t.stamp

let string_of_blank_id id = id;;
let blank_id_of_string str = str;;

let blank str = Blank_ (blank_id_of_string str)
let blank_ id = Blank_ id

let term_of_iri_string s = Iri (Iri.of_string s);;
let mk_literal ?typ ?lang v =
  { lit_value = v ; lit_language = lang ; lit_type = typ ; }
;;
let term_of_literal_string ?typ ?lang v =
  Literal (mk_literal ?typ ?lang v)
;;

let now () = 
  match Ptime.of_float_s (Unix.gettimeofday()) with
    None -> assert false
  | Some stamp -> { stamp ; tz = None }
let mk_literal_datetime ?(d=now()) () =
  let v = string_of_datetime d in
  mk_literal ~typ: (Iri.of_string "http://www.w3.org/2001/XMLSchema#dateTime") v
;;

let term_of_datetime ?d () =
  Literal (mk_literal_datetime ?d ())
;;

let datetime_of_literal lit = datetime_of_string lit.lit_value

let mk_literal_bool b =
  let v = if b then "1" else "0" in
  mk_literal ~typ: Rdf_rdf.xsd_boolean v
;;

let mk_literal_int ?(typ=Rdf_rdf.xsd_integer) n =
  mk_literal ~typ (string_of_int n)
;;

let mk_literal_double f =
  mk_literal ~typ: Rdf_rdf.xsd_double (string_of_float f)
;;

let term_of_int ?typ n = Literal (mk_literal_int ?typ n)
let term_of_double f = Literal (mk_literal_double f)
let term_of_bool b = Literal (mk_literal_bool b);;

let bool_of_literal lit =
  match lit.lit_value with
    "1" | "true" -> true
  | _ -> false
;;

(** We must not escape \u sequences used to encode UTF-8 characters.
  Since String.escaped escapes all '\\', then unescape "\\u" back to "\u".
*)
let unescape_backslash_u s =
  let len = String.length s in
  let b = Buffer.create len in
  let rec iter p =
    if p < len - 3 then
      match s.[p], s.[p+1], s.[p+2] with
        '\\', '\\', 'u' -> Buffer.add_string b "\\u" ; iter (p+3)
      | '\\', '\\', 'U' -> Buffer.add_string b "\\U" ; iter (p+3)
      | c, _, _ -> Buffer.add_char b c; iter (p+1)
    else if p < len then
        (
         Buffer.add_char b s.[p] ;
         iter (p+1)
        )
  in
  iter 0;
  Buffer.contents b
;;

let quote_str s = "\""^(Rdf_utf8.utf8_escape s)^"\"";;

let string_of_literal lit =
  (quote_str lit.lit_value) ^
    (match lit.lit_language with
       None -> ""
     | Some l -> "@" ^ l
    ) ^
    (match lit.lit_type with
       None -> ""
     | Some t -> "^^<" ^ (Iri.to_string t) ^ ">"
    )

let string_of_term = function
| Iri iri -> "<" ^ (Iri.to_string iri) ^ ">"
| Literal lit -> string_of_literal lit
| Blank -> "_"
| Blank_ id ->  "_:" ^ (string_of_blank_id id)
;;

let int64_hash str =
  let digest = Digest.string str in
  (* use the same method as in librdf: use the 8 first bytes to
     get a 64 bits integer independant from the little/big endianness *)
  let hash = ref Int64.zero in
  for i = 0 to 7 do
    hash := Int64.add !hash (Int64.shift_left (Int64.of_int (Char.code digest.[i])) (i*8))
  done;
  !hash
;;

let term_hash = function
  Iri iri -> int64_hash ("R" ^ (Iri.to_string iri))
| Literal lit ->
    int64_hash (
     "L" ^
       lit.lit_value ^ "<" ^
       (Rdf_misc.string_of_opt lit.lit_language) ^ ">" ^
       (Rdf_misc.string_of_opt (Rdf_misc.map_opt Iri.to_string lit.lit_type))
    )
| Blank -> assert false
| Blank_ id -> int64_hash ("B" ^ (string_of_blank_id id))
;;

let compare term1 term2 =
  match term1, term2 with
    Iri iri1, Iri iri2 -> Iri.compare iri1 iri2
  | Iri _, _ -> 1
  | _, Iri _ -> -1
  | Literal lit1, Literal lit2 ->
      begin
        match String.compare lit1.lit_value lit2.lit_value with
          0 ->
            begin
              match Rdf_misc.opt_compare String.compare
                lit1.lit_language lit2.lit_language
              with
                0 ->
                  Rdf_misc.opt_compare Iri.compare
                    lit1.lit_type lit2.lit_type
              | n -> n
            end
        | n -> n
      end
  | Literal _, _ -> 1
  | _, Literal _ -> -1
  | Blank, Blank -> 0
  | Blank, _ -> 1
      | _, Blank -> -1
  | Blank_ id1, Blank_ id2 ->
      String.compare
        (string_of_blank_id id1)
        (string_of_blank_id id2)

module Ordered_term =
  struct
    type t = term
    let compare = compare
  end;;

module TSet = Set.Make (Ordered_term);;
module TMap = Map.Make (Ordered_term);;

let lit_true = mk_literal_bool true
let lit_false = mk_literal_bool false
