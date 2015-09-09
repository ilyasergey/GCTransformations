Require Import Ssreflect.ssreflect Ssreflect.ssrbool Ssreflect.ssrnat.
Require Import Ssreflect.eqtype Ssreflect.ssrfun Ssreflect.seq.
Require Import MathComp.path.
Require Import Eqdep pred prelude idynamic ordtype pcm finmap unionmap heap coding. 
Require Import hgraphs logs wavefronts.
Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive. 

Section Partitions.

(* Abstract interface for two-partition of the object space *)

Structure par2 := Par2 {
  pr1 : ptr -> bool;
  pr2 : ptr -> bool;
  pr_coh : forall o, addb (pr1 o) (pr2 o)
}.

End Partitions.

Section WavefrontDimension.

(* Initial graph an heap *)
Variables (h0 : heap) (g0: graph h0).

(* A collector log p will all unique entires *)
Variables  (p : log).

(* Final heap and graph for the log p with the corresponding certificate epf *)
Variables (h : heap) (g: graph h).
Variable (epf : executeLog g0 p = Some (ExRes g)).

Variable wp : par2.
Notation FL := (pr1 wp).
Notation OL := (pr2 wp).

Eval compute in iota 0 3.

Definition all_obj_fields (e : ptr) := 
    [seq (e, f) | f <- iota 0 (size (fields g e))]. 

Definition all_obj_fields_wf l :=
    flatten [seq (all_obj_fields e.1) | e <- wavefront l].

(* W_gt approximates the set of object fields behind the wavefront by
   taking all_obj_fields of an object instead specific traced fields
   in the wavefront. *)

Definition W_gt := 
   let wfl := [seq ef <- wavefront p         | FL ef.1] in
   let wol := [seq ef <- all_obj_fields_wf p | OL ef.1] in
       wfl ++ wol.

Lemma w_gt_approx : {subset wavefront p <= W_gt}.
Proof.
move=>o. rewrite /W_gt mem_cat !mem_filter.
case X: (FL o.1)=>//=H; first by rewrite H.
move: (pr_coh wp (o.1)); rewrite X=>/=->/=.
apply/flatten_mapP; exists o=>//.
apply/mapP; exists o.2; last by rewrite -surjective_pairing.
case: (wavefront_trace H)=>e[l1][l2][H1]H2 H3 H4.
move: (trace_fsize epf H2 H1); rewrite H3 H4.
by rewrite mem_iota add0n. 
Qed.


(* TODO *)

Definition W_lt := 
   let wfl := [seq ef | ef <- wavefront p & FL ef.1] in
   let wol := [seq ef | ef <- wavefront p & 
                        (OL ef.1) && (ef \in all_obj_fields_wf p)] in
       wfl ++ wol.

End WavefrontDimension.
