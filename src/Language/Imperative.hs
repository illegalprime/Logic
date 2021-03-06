module Language.Imperative where

import           Control.Monad.State

import           Data.Data (Data)
import           Data.Tuple (swap)
import qualified Data.Ord.Graph as G
import           Data.Ord.Graph (Graph)
import           Data.Set (Set)
import qualified Data.Set as S
import           Data.Map (Map)
import qualified Data.Map as M
import           Data.Text.Prettyprint.Doc

import           Logic.Type as T
import           Logic.Formula
import           Logic.Var
import           Logic.Chc

-- | The space of imperative programs are represented as inductively constructed
-- commands.
data Comm
  = Seq Comm Comm
  | Case Form Comm Comm
  | Loop Form Comm
  | Ass Var RHS
  | Skip
  | Lbl Int Comm
  | Jump Int
  | Save Name Form Form
  deriving (Show, Eq, Ord, Data)

-- | The right hand side of an assignment.
data RHS
  = Expr Form
  | Arbitrary Type
  | Load Name Form
  deriving (Show, Eq, Ord, Data)

commChc :: Comm -> [Chc]
commChc = undefined

type Lbl = Int

-- | Semantic actions of a program which can be represented as a single logical
-- formula. This is limited to combinations of conditionals and assignments.
data SemAct
  = SemSeq SemAct SemAct
  | SemAss Var RHS
  | SemCase Form SemAct SemAct
  | SemSkip
  | SemPredicate Form
  | SemSave Name Form Form
  deriving (Show, Eq, Ord, Data)

semantics :: SemAct -> (Form, Map Var Var)
semantics ac = let (f, (m, _)) = runState (sem ac) (M.empty, S.empty)
               in (f, m)
  where
    sem = \case
      SemSeq a1 a2 -> mkAnd <$> sem a1 <*> sem a2
      SemAss v rhs -> do
        (m, s) <- get
        let v' = fresh s v
        e <- case rhs of
          Arbitrary _ -> return (LBool True)
          Expr e' -> do
            let e'' = subst m e'
            return (app2 (Eql $ typeOf v') (V v') e'')
          Load{} ->
            -- Load statements cannot translated to formulas.
            return (LBool False)
        put (M.insert v v' m, S.insert v' s)
        return e
      SemCase e a1 a2 -> do
        (m, s) <- get
        let e' = subst m e
        sem1 <- sem a1
        (m1, s1) <- get
        put (m, s)
        sem2 <- sem a2
        (m2, s2) <- get
        let (m1', as1) = mergeBranch s2 s1 m2 m1
        let sem1' = mkAnd sem1 as1
        let (_  , as2) = mergeBranch s1 s2 m1 m2
        let sem2' = mkAnd sem2 as2
        put (m1', S.union s1 s2)
        return (appMany (If T.Bool) [e', sem1', sem2'])
      SemSkip         -> return (LBool True)
      SemPredicate e  -> do
        (m, _) <- get
        return $ subst m e
      SemSave{} ->
        -- Save statements cannot translated to formulas.
        return (LBool False)

    -- | On if branches, one branch might alias a variable more than the other.
    -- To account for this, we decide how to update the variables after the
    -- semantic action of the branch.
    mergeBranch s1 s2 m1 m2 =
      let updateNeeded = S.toList $ s1 S.\\ s2
          invM1 = M.fromList $ map swap $ M.toList m1
          originals = map (subst invM1) updateNeeded
          branched = map (subst m2) originals
          eqs = zipWith (\v1 v2 -> app2 (Eql (typeOf v1)) (V v1) (V v2)) updateNeeded branched
          m1' = foldr (\(v1, v2) m -> M.insert v1 v2 m) m1 (zip originals branched)
      in (m1', manyAnd eqs)

semSeq :: SemAct -> SemAct -> SemAct
semSeq SemSkip s = s
semSeq s SemSkip = s
semSeq s1 s2 = SemSeq s1 s2

-- | `simple` commands are those which can appear directly as a semantic
-- action.
isSimple :: Comm -> Bool
isSimple = \case
  Seq c1 c2    -> isSimple c1 && isSimple c2
  Case _ c1 c2 -> isSimple c1 && isSimple c2
  Loop _ _     -> False
  Lbl _ _      -> False
  Jump _       -> False
  Ass _ _      -> True
  Skip         -> True
  Save{}      -> True

-- | Convert a command to a semantic action. Only a subset of commands are
-- convertible to semantic actions, any in general full commands should be
-- converted to structured actions.
commSem :: Comm -> SemAct
commSem = \case
  Seq c1 c2    -> semSeq (commSem c1) (commSem c2)
  Case e c1 c2 -> SemCase e (commSem c1) (commSem c2)
  Ass v e      -> SemAss v e
  Loop _ _     -> SemSkip
  Lbl _ _      -> SemSkip
  Jump _       -> SemSkip
  Skip         -> SemSkip
  Save f i v   -> SemSave f i v

-- | A flow graph presents the semantic actions of the program as vertices with
-- transition formulas on the edges. The semantic actions are labelled with the
-- variables that are live at the end of the semantic action.
data FlowGr = FlowGr
  { getFlowGr :: Graph Int SemAct (Set Var)
  , entrance :: Int
  , exit :: Int
  }

data PartGraph = PartGraph (Graph Int SemAct ()) Int SemAct

commGraph :: Comm -> Graph Int SemAct ()
commGraph comm =
  renumber $ evalState (do
    i <- initial
    f <- commGraph' comm i
    terminate f) (0, M.empty)
  where
    commGraph' :: Comm -> PartGraph -> State (Lbl, Map Int Lbl) PartGraph
    commGraph' comm' pg@(PartGraph g n s)
      | isSimple comm' = return $ PartGraph g n (semSeq (commSem comm') s)
      | otherwise = case comm' of
        Seq c1 c2 -> commGraph' c2 pg >>= commGraph' c1
        Case e c1 c2 -> do
          (PartGraph g1 n1 s1) <- commGraph' c1 pg
          (PartGraph g2 n2 s2) <- commGraph' c2 pg
          h <- vert
          let g' = G.addEdge h n1 (semSeq (SemPredicate e) s1)
                 $ G.addEdge h n2 (semSeq (SemPredicate (Not :@ e)) s2)
                 $ G.addVert h ()
                 $ G.union g1 g2
          return $ PartGraph g' h SemSkip
        Loop e c -> do
          h <- vert
          (PartGraph g' en' s') <- commGraph' c (PartGraph (G.addVert h () G.empty) h SemSkip)
          let g'' = G.addEdge h en' (semSeq (SemPredicate e) s') g'
          return $ PartGraph
              ( G.addEdge h n (semSeq (SemPredicate (Not :@ e)) s)
              $ G.union g g'')
              h SemSkip
        Skip -> return pg
        Jump l -> skipTo g <$> lblVert l
        Lbl l c -> do
          v <- lblVert l
          (PartGraph g' en s') <- commGraph' c pg
          return $ PartGraph ( G.addEdge v en s'
                             $ G.addVert v () g'
                             ) v SemSkip
        _ -> return $ PartGraph g n (semSeq (commSem comm') s)
    lblVert l = do
      m <- snd <$> get
      case M.lookup l m of
        Just v -> return v
        Nothing -> do
          v <- vert
          modify (\(v', _) -> (v', M.insert l v m))
          return v
    vert = state (\(v, m) -> (v, (v+1, m)))
    initial = skipTo G.empty <$> vert
    skipTo g n = PartGraph (G.addVert n () g) n SemSkip
    terminate (PartGraph g en s) =
      if s == SemSkip then return g
      else do
        v <- vert
        return $ G.addEdge v en s $ G.addVert v () g
    renumber :: Graph Int a () -> Graph Int a ()
    renumber g =
      let n = G.order g
          ren = M.fromList (zip [n-1,n-2..0] [0..n-1])
      in G.mapIdxs (\i -> M.findWithDefault (-1) i ren) g

instance Pretty Comm where
  pretty = \case
    Seq c1 c2    -> vsep [pretty c1, pretty c2]
    Case e c1 c2 ->
      vsep [ pretty "IF" <+> pretty e
           , nest 2 (pretty c1)
           , pretty "ELSE"
           , nest 2 (pretty c2) ]
    Loop e c     -> vsep [pretty "WHILE" <+> pretty e, nest 2 (pretty c)]
    Ass v r      -> hsep [pretty v, pretty ":=", pretty r]
    Skip         -> pretty "SKIP"
    Lbl l c      -> vsep [pretty ("LABEL: " ++ show l), pretty c]
    Jump l       -> pretty ("JUMP: " ++ show l)
    Save f i v   -> hsep [pretty "SAVE", pretty f, pretty i, pretty v]

instance Pretty RHS where
  pretty = \case
    Expr f -> pretty f
    Arbitrary t -> pretty "ANY" <+> pretty t
    Load f i -> hsep [pretty "LOAD", pretty f, pretty i]

instance Pretty SemAct where
  pretty = \case
    SemSeq a1 a2    -> vsep [pretty a1 <> pretty ";", pretty a2]
    SemAss v r      -> hsep [pretty v, pretty ":=", pretty r]
    SemPredicate e  -> pretty e
    SemCase e c1 c2 ->
      vsep [ pretty "IF" <+> pretty e
           , nest 2 (pretty c1)
           , pretty "ELSE"
           , nest 2 (pretty c2) ]
    SemSkip         -> pretty "SKIP"
    SemSave f i v  -> hsep [pretty "SAVE", pretty f, pretty i, pretty v]
