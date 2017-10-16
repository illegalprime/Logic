{-# LANGUAGE QuasiQuotes, LambdaCase #-}

import           Control.Lens
import           Control.Monad.State
import           Control.Monad.Except

import qualified Data.Graph.Inductive.Graph as G
import qualified Data.Graph.Inductive.Extras as G
import qualified Data.Map as M
import           Data.Maybe

import qualified Logic.Type as T
import           Logic.Formula
import           Logic.Formula.Parser
import           Logic.Var
import           Logic.ImplicationGraph
import           Logic.ImplicationGraph.Type
import           Text.PrettyPrint.HughesPJClass

h, h', t, t', i, i', c, c', n, next, next' :: Var
h  = Free "h"  T.Int
h' = Free "h'" T.Int
t  = Free "t"  T.Int
t' = Free "t'" T.Int
i  = Free "i"  T.Int
i' = Free "i'" T.Int
c  = Free "c"  T.Int
c' = Free "c'" T.Int
n  = Free "n" T.Int
next  = Free "next" (T.Array T.Int T.Int)
next' = Free "next" (T.Array T.Int T.Int)

s :: [Var]
s = [h, t, i, c, n, next]

-- example :: Comm
-- example = Seq
--   (Ass h (Expr [form|1|])) $ Seq
--   (Ass t (Expr (V h))) $ Seq
--   (Ass i (Expr [form|2|])) $ Seq
--   (Ass c (Expr [form|0|])) $ Seq
--   (Loop [form|c:Int < n:Int|] $ Seq
--     (Save "next" (V t) (V i)) $ Seq
--     (Ass t (Expr (V i)))
--     (Ass i (Expr [form|i:Int + 1|]))) $ Seq
--   (Ass c (Expr [form|0|]))
--   (Loop [form|c:Int < n:Int|]
--     (Ass h (Load "next" (V h))))

g :: ImplGr
g =
  G.insEdge (0, 1, ImplGrEdge [form| h:Int = 1
                                  && t:Int = 1
                                  && i:Int = 2
                                  && c:Int = 0|]
                              M.empty) $
  G.insEdge (1, 1, ImplGrEdge [form| c:Int < n:Int
                                  && next':Arr{Int,Int} = store next:Arr{Int,Int} t:Int i:Int
                                  && t':Int = i:Int
                                  && i':Int = i:Int + 1
                                  && c':Int = c:Int + 1|]
                              (M.fromList [(next, next'), (t, t'), (i, i'), (c, c')])) $
  G.insEdge (1, 2, ImplGrEdge [form| c:Int >= n:Int && c':Int = 0|]
                              (M.singleton c c')) $
  G.insEdge (2, 2, ImplGrEdge [form| c:Int < n:Int
                                  && c':Int = c:Int + 1
                                  && h':Int = select next:Arr{Int,Int} h:Int |]
                              (M.fromList [(h, h'), (c, c')])) $
  G.insEdge (2, 3, ImplGrEdge [form|c:Int >= n:Int|] M.empty) $
  G.insNode (0, InstanceNode (mkInstance [0, 0] [])) $
  G.insNode (1, InstanceNode (mkInstance [1, 1] s)) $
  G.insNode (2, InstanceNode (mkInstance [2, 2] s)) $
  G.insNode (3, QueryNode [form|h:Int = t:Int|])
  G.empty

storeEdges :: ImplGr -> [(G.Node, G.Node, ImplGrEdge)]
storeEdges g = undefined

removeStores :: Form -> Form
removeStores = undefined

storeElimination :: ImplGr -> ImplGr
storeElimination g = foldr elim g (storeEdges g)

  where
    elim :: (G.Node, G.Node, ImplGrEdge) -> ImplGr -> ImplGr
    elim (n1, n2, ImplGrEdge f m) g =
      let (InstanceNode i) = G.vertex n1 g
          f' = removeStores f
          g' = G.insEdge (n1, n2, ImplGrEdge f' m) $ G.delEdge (n1, n2) g
          re = G.reached n1 g
          swpPos2 = g
            & G.labnfilter (\(_, l) -> case l of
                InstanceNode i' -> head (i' ^. identity) == (i' ^. identity) !! 1
                _ -> True)
            & G.nmap (\case
                InstanceNode i' -> InstanceNode (i' & identity . ix 1 .~ (fromJust $ i ^? identity . ix 0))
                n' -> n')
      in undefined

main :: IO ()
main = do
  G.display "shape" g
  sol <- evalStateT (runExceptT $ step [4] g) emptySolveState
  case sol of
    Left (Failed m) -> putStrLn $ prettyShow m
    Left (Complete g') -> do
      putStrLn "Done!"
      G.display "shape-2" g'
    Right g' -> G.display "shape-2" g'
