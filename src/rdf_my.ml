(*********************************************************************************)
(*                OCaml-RDF                                                      *)
(*                                                                               *)
(*    Copyright (C) 2012 Institut National de Recherche en Informatique          *)
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

(** MySQL storage. *)

open Rdf_node;;

let dbg = Rdf_misc.create_log_fun
  ~prefix: "Rdf_my"
    "RDF_MY_DEBUG_LEVEL"
;;

type t =
  { g_name : Rdf_uri.uri ; (* graph name *)
    g_table : string ; (* name of the table with the statements *)
    g_dbd : Mysql.dbd ;
    mutable g_in_transaction : bool ;
  }

type error = string
exception Error = Mysql.Error
let string_of_error s = s;;

let exec_query dbd q =
  dbg ~level: 2 (fun () -> Printf.sprintf "exec_query: %s" q);
  let res = Mysql.exec dbd q in
  match Mysql.status dbd with
    Mysql.StatusOK | Mysql.StatusEmpty -> res
  | Mysql.StatusError _ ->
      let msg = Rdf_misc.string_of_opt (Mysql.errmsg dbd) in
      raise (Error msg)
;;

let db_of_options options =
  let dbhost = Rdf_misc.opt_of_string
    (Rdf_graph.get_option ~def: "" "host" options)
  in
  let dbname  = Rdf_misc.opt_of_string
    (Rdf_graph.get_option "database" options)
  in
  let dbport  = Rdf_misc.map_opt int_of_string
    (Rdf_misc.opt_of_string (Rdf_graph.get_option ~def: "" "port" options))
  in
  let dbpwd  = Rdf_misc.opt_of_string
    (Rdf_graph.get_option ~def: "" "password" options)
  in
  let dbuser  = Rdf_misc.opt_of_string
    (Rdf_graph.get_option "user" options)
  in
  { Mysql.dbhost = dbhost ; dbname ; dbport ; dbpwd ; dbuser ; dbsocket = None }

;;

let hash_of_node dbd ?(add=false) node =
  let hash = Rdf_node.node_hash node in
  if add then
    begin
      let test_query = Printf.sprintf
        "SELECT COUNT(*) FROM %s WHERE id=%Ld"
        (match node with
           Uri _ -> "resources"
         | Literal _ -> "literals"
         | Blank_ _ | Blank -> "bnodes"
        )
        hash
      in
      match Mysql.fetch (exec_query dbd test_query) with
        Some [| Some s |] when int_of_string s = 0 ->
          let pre_query =
            match node with
              Uri uri ->
                Printf.sprintf "resources (id, value) values (%Ld, %S)"
                hash (Rdf_uri.string uri)
            | Literal lit ->
                Printf.sprintf
                "literals (id, value, language, datatype) \
             values (%Ld, %S, %S, %S)"
                hash
                lit.lit_value
                (Rdf_misc.string_of_opt lit.lit_language)
                (Rdf_misc.string_of_opt (Rdf_misc.map_opt Rdf_uri.string lit.lit_type))
            | Blank_ id ->
                Printf.sprintf "bnodes (id, value) values (%Ld, %S)"
                hash (Rdf_node.string_of_blank_id id)
            | Blank -> assert false
          in
          let query = Printf.sprintf "INSERT INTO %s" pre_query (* ON DUPLICATE KEY UPDATE value=value*) in
          ignore(exec_query dbd query)
      | _ -> ()
    end;
  hash
;;


let table_options = " ENGINE=InnoDB DELAY_KEY_WRITE=1 MAX_ROWS=100000000 DEFAULT CHARSET=UTF8";;
let creation_queries =
  [
    "CREATE TABLE IF NOT EXISTS graphs (id integer AUTO_INCREMENT PRIMARY KEY NOT NULL, name text NOT NULL)" ;
    "CREATE TABLE IF NOT EXISTS bnodes (id bigint PRIMARY KEY NOT NULL, value text NOT NULL) AVG_ROW_LENGTH=33" ;
    "CREATE TABLE IF NOT EXISTS resources (id bigint PRIMARY KEY NOT NULL, value text NOT NULL) AVG_ROW_LENGTH=80";
    "CREATE TABLE IF NOT EXISTS literals (id bigint PRIMARY KEY NOT NULL, value longtext NOT NULL,
                                          language text, datatype text)  AVG_ROW_LENGTH=50" ;
  ]
;;

let init_db db =
  let dbd = Mysql.connect db in
  List.iter
  (fun q -> ignore (exec_query dbd (q^table_options))) creation_queries;
  dbd
;;

let graph_table_of_id id = Printf.sprintf "graph%d" id;;

let rec graph_table_of_graph_name ?(first=true) dbd uri =
  let name = Rdf_uri.string uri in
  let query = Printf.sprintf "SELECT id FROM graphs WHERE name = %S" name in
  let res = exec_query dbd query in
  match Mysql.fetch res with
    Some [| Some id |] -> graph_table_of_id (int_of_string id)
  | _ when not first ->
      let msg = Printf.sprintf "Could not get table name for graph %S" name in
      raise (Error msg)
  | _ ->
      let query = Printf.sprintf "INSERT INTO graphs (name) VALUES (%S)" name in
      ignore(exec_query dbd query);
      graph_table_of_graph_name ~first: false dbd uri
;;

let table_exists dbd table =
  let query = Printf.sprintf "SELECT 1 FROM %s" table in
  try ignore(exec_query dbd query); true
  with Error _ -> false
;;

let init_graph dbd name =
  let table = graph_table_of_graph_name dbd name in
  if not (table_exists dbd table) then
    begin
      let query = Printf.sprintf
        "CREATE TABLE IF NOT EXISTS %s (\
         subject bigint NOT NULL, predicate bigint NOT NULL, \
         object bigint NOT NULL,\
         KEY SubjectPredicate (subject,predicate),\
         KEY PredicateObject (predicate,object),\
         KEY ObjectSubject (object,subject)\
        ) %s AVG_ROW_LENGTH=59"
        table table_options
      in
      ignore(exec_query dbd query);
(*
      let query = Printf.sprintf
        "ALTER TABLE %s ADD UNIQUE INDEX (subject, predicate, object)" table
      in
      ignore(exec_query dbd query)
*)
    end;
  table
;;

let node_of_hash dbd hash =
  let query = Printf.sprintf
    "SELECT NULL, value, NULL, NULL, NULL FROM resources where id=%Ld UNION \
     SELECT NULL, NULL, value, language, datatype FROM literals where id=%Ld UNION \
     SELECT value, NULL, NULL, NULL, NULL FROM bnodes where id=%Ld"
    hash hash hash
  in
  let res = exec_query dbd query in
  let size = Mysql.size res in
  match Int64.compare size Int64.one with
    n when n > 0 ->
      let msg = Printf.sprintf "No node with hash \"%Ld\"" hash in
      raise (Error msg)
  | 0 ->
      begin
        match Mysql.fetch res with
          None -> assert false (* already tested: there is at least one row *)
        | Some t ->
            match t with
              [| Some name ; None ; None ; None ; None |] ->
                Blank_ (Rdf_node.blank_id_of_string name)
            | [| None ; Some uri ; None ; None ; None |] ->
                Rdf_node.node_of_uri_string uri
            | [| None ; None ; Some value ; lang ; typ |] ->
                let typ = Rdf_misc.map_opt
                  Rdf_uri.uri
                  (Rdf_misc.opt_of_string (Rdf_misc.string_of_opt typ))
                in
                Rdf_node.node_of_literal_string
                ?lang: (Rdf_misc.opt_of_string (Rdf_misc.string_of_opt lang))
                ?typ value
            | _ ->
                let msg = Printf.sprintf "Bad result for node with hash \"%Ld\"" hash in
                raise (Error msg)
      end
  | _ ->
      let msg = Printf.sprintf "More than one node found with hash \"%Ld\"" hash in
      raise (Error msg)
;;

let query_node_list g field where_clause =
  let query = Printf.sprintf "SELECT  %s FROM %s where %s" (* removed DISTINCT *)
    field g.g_table where_clause
  in
  let res = exec_query g.g_dbd query in
  let f = function
  | [| Some hash |] ->
      node_of_hash g.g_dbd (Mysql.int642ml hash)
  | _ -> raise (Error "Invalid result: NULL hash or too many fields")
  in
  Mysql.map res ~f
;;

let query_triple_list g where_clause =
  let query = Printf.sprintf
    "SELECT subject, predicate, object FROM %s where %s" (* removed DISTINCT *)
    g.g_table where_clause
  in
  let res = exec_query g.g_dbd query in
  let f = function
  | [| Some sub ; Some pred ; Some obj |] ->
      (node_of_hash g.g_dbd (Mysql.int642ml sub),
       node_of_hash g.g_dbd (Mysql.int642ml pred),
       node_of_hash g.g_dbd (Mysql.int642ml obj)
      )
  | _ -> raise (Error "Invalid result: NULL hash(es) or bad number of fields")
  in
  Mysql.map res ~f
;;

let open_graph ?(options=[]) name =
  let db = db_of_options options in
  let dbd = init_db db in
  let table_name = init_graph dbd name in
  { g_name = name ;
    g_table = table_name ;
    g_dbd = dbd ;
    g_in_transaction = false ;
  }
;;

let add_triple g ~sub ~pred ~obj =
  let sub = hash_of_node g.g_dbd ~add:true sub in
  let pred = hash_of_node g.g_dbd ~add:true pred in
  let obj = hash_of_node g.g_dbd ~add:true obj in
  (* do not insert if already present *)
  let query = Printf.sprintf
    "SELECT COUNT(*) FROM %s WHERE subject=%Ld AND predicate=%Ld AND object=%Ld"
    g.g_table sub pred obj
  in
  match Mysql.fetch (exec_query g.g_dbd query) with
    Some [| Some s |] when int_of_string s = 0 ->
      let query = Printf.sprintf
        "INSERT INTO %s (subject, predicate, object) VALUES (%Ld, %Ld, %Ld) ON DUPLICATE KEY UPDATE subject=subject"
        g.g_table sub pred obj
      in
      ignore(exec_query g.g_dbd query)
  | _ -> ()
;;

let rem_triple g ~sub ~pred ~obj =
  let sub = hash_of_node g.g_dbd ~add:false sub in
  let pred = hash_of_node g.g_dbd ~add:false pred in
  let obj = hash_of_node g.g_dbd ~add:false obj in
  let query = Printf.sprintf
    "DELETE FROM %s WHERE subject=%Ld AND predicate=%Ld AND object=%Ld"
    g.g_table sub pred obj
  in
  ignore(exec_query g.g_dbd query)
;;

let subjects_of g ~pred ~obj =
  query_node_list g "subject"
  (Printf.sprintf "predicate=%Ld AND object=%Ld"
   (hash_of_node g.g_dbd pred) (hash_of_node g.g_dbd obj))
;;

let predicates_of g ~sub ~obj =
  query_node_list g "predicate"
  (Printf.sprintf "subject=%Ld AND object=%Ld"
   (hash_of_node g.g_dbd sub) (hash_of_node g.g_dbd obj))
;;

let objects_of g ~sub ~pred =
  query_node_list g "object"
  (Printf.sprintf "subject=%Ld AND predicate=%Ld"
   (hash_of_node g.g_dbd sub) (hash_of_node g.g_dbd pred))
;;

let mk_where_clause ?sub ?pred ?obj g =
  let mk_cond field = function
    None -> []
  | Some node ->
      [Printf.sprintf "%s=%Ld" field (hash_of_node g.g_dbd node)]
  in
  match sub, pred, obj with
    None, None, None -> "TRUE"
  | _ ->
      let l =
        (mk_cond "subject" sub) @
        (mk_cond "predicate" pred) @
        (mk_cond "object" obj)
      in
      String.concat " AND " l
;;

let find ?sub ?pred ?obj g =
  let clause = mk_where_clause ?sub ?pred ?obj g in
  query_triple_list g clause
;;

let exists ?sub ?pred ?obj g =
  let query = Printf.sprintf "SELECT COUNT(*) FROM %s where %s"
    g.g_table (mk_where_clause ?sub ?pred ?obj g)
  in
  let res = exec_query g.g_dbd query in
  match Mysql.fetch res with
    Some [| Some n |] -> int_of_string n > 0
  | _ ->
    let msg = Printf.sprintf "Bad result for query: %s" query in
    raise (Error msg)
;;

let subjects g = query_node_list g "subject" "TRUE";;
let predicates g = query_node_list g "predicate" "TRUE";;
let objects g = query_node_list g "object" "TRUE";;

let transaction_start g =
  if g.g_in_transaction then
    raise (Error "Already in a transaction. Nested transactions not allowed.");
  ignore(exec_query g.g_dbd "START TRANSACTION");
  g.g_in_transaction <- true
;;

let transaction_commit g =
 if not g.g_in_transaction then
    raise (Error "Not in a transaction.");
  ignore(exec_query g.g_dbd "COMMIT");
  g.g_in_transaction <- false
;;

let transaction_rollback g =
 if not g.g_in_transaction then
    raise (Error "Not in a transaction.");
  ignore(exec_query g.g_dbd "ROLLBACK");
  g.g_in_transaction <- false
;;

let new_blank_id g =
  let cardinal =
    let query = Printf.sprintf "SELECT COUNT(*) FROM %s" g.g_table in
    let res = exec_query g.g_dbd query in
    match Mysql.fetch res with
      Some [|Some s|] -> int_of_string s
    | _ -> 0
  in
  let max_int = Int32.to_int (Int32.div Int32.max_int (Int32.of_int 2)) in
  Rdf_node.blank_id_of_string
  (Printf.sprintf "%d-%d" cardinal (Random.int max_int))
;;

module Mysql =
  struct
    let name = "mysql"
    type g = t
    type error = string
    exception Error = Error
    let string_of_error s = s

    let graph_name g = g.g_name

    let open_graph = open_graph

    let add_triple = add_triple
    let rem_triple = rem_triple

    let add_triple_t g (sub, pred, obj) = add_triple g ~sub ~pred ~obj
    let rem_triple_t g (sub, pred, obj) = rem_triple g ~sub ~pred ~obj

    let subjects_of = subjects_of
    let predicates_of = predicates_of
    let objects_of = objects_of

    let find = find
    let exists = exists
    let exists_t (sub, pred, obj) g = exists ~sub ~pred ~obj g

    let subjects = subjects
    let predicates = predicates
    let objects = objects

    let transaction_start = transaction_start
    let transaction_commit = transaction_commit
    let transaction_rollback = transaction_rollback

    let new_blank_id = new_blank_id
  end;;

Rdf_graph.add_storage (module Mysql : Rdf_graph.Storage);;



