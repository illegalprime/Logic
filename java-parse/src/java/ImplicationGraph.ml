open Core

module QID = QualifiedIdentity
module Env = Sawja_pack.Live_bir.Env

module Edge = struct
  type t = {
      formula: Ir.expr;
      rename: (string * string) list;
    }
  [@@deriving hash, compare]

  let default = { formula = Ir.LBool true; rename = [] }
  let equal = (=)
end

module Vertex = struct
  type t = {
      loc: QualifiedIdentity.t;
      live: string list;
    }
  [@@deriving hash, compare]

  let equal = (=)
end

include Graph.Persistent.Digraph.ConcreteBidirectionalLabeled(Vertex)(Edge)


let to_implication
      (instr_graph: InstrGraph.t)
      vartable
  =
  let build
        ((v: InstrGraph.V.t), (e: InstrGraph.E.label), (v': InstrGraph.V.t))
        (graph: t) =
    let open Vertex in
    let open Edge in
    let live_names env = env |> Env.elements |> List.map ~f:InstrGraph.var_name in
    let start = {
        loc = v.InstrGraph.Instr.loc;
        live = live_names v.InstrGraph.Instr.live;
      } in
    let finish = {
        loc = v'.InstrGraph.Instr.loc;
        live = live_names v'.InstrGraph.Instr.live;
      } in
    let instr = v.InstrGraph.Instr.instr in
    let (expr, rename) = match (InstrGraph.instr_to_expr vartable instr, e) with
      | (None, _) -> (Ir.LBool true, String.Map.empty)
      | (Some (expr, r), InstrGraph.Branch.True) -> (expr, r)
      | (Some (expr, r), InstrGraph.Branch.Goto) -> (expr, r)
      | (Some (expr, r), InstrGraph.Branch.False) -> (Ir.ExprCons (Ir.Not, expr), r)
    in
    let edge = {
        formula = expr;
        rename = String.Map.to_alist rename;
      } in
    add_edge_e graph (E.create start edge finish)
  in
  InstrGraph.fold_edges_e build instr_graph empty


let serialize (graph: t) =
  let collect_vertices v l =
    let open Vertex in
    let lives = v.live
                |> List.map ~f:(fun var -> Printf.sprintf "\"%s\"" var)
                |> String.concat ~sep:","
    in
    (Printf.sprintf "\"%s\":[%s]" (QID.as_path v.loc) lives) :: l
  in
  let vertices = fold_vertex collect_vertices graph [] in
  let vlist = String.concat vertices ~sep:"," |> Printf.sprintf "{%s}" in
  let rename_str r =
    List.map ~f:(fun (a, b) -> Printf.sprintf "{\"%s\":\"%s\"}" a b) r
    |> String.concat ~sep:","
    |> Printf.sprintf "[%s]"
  in
  let edge_str (v, e, v') l =
    let open Edge in
    let open Vertex in
    Printf.sprintf "{\"start\":\"%s\",\"end\":\"%s\",\"formula\":%s,\"rename\":%s}"
                   (QID.as_path v.loc)
                   (QID.as_path v'.loc)
                   (Ir.jsonsexp_expr e.formula)
                   (rename_str e.rename)
    :: l
  in
  let edges = fold_edges_e edge_str graph [] in
  let elist = String.concat ~sep:"," edges |> Printf.sprintf "[%s]" in
  Printf.sprintf "{\"edges\":%s,\"vertices\":%s}" elist vlist
