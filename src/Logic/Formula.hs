{-# LANGUAGE LambdaCase
           , DeriveDataTypeable
           , FlexibleContexts
           , FlexibleInstances
           , OverloadedStrings
           , PatternSynonyms
           #-}

module Logic.Formula where

import           Control.Lens

import           Data.Data (Data)
import           Data.Data.Lens (biplate, uniplate)
import qualified Data.Map as M
import qualified Data.Set as S

import           Logic.Type (Type((:=>)), Typed)
import qualified Logic.Type as T
import           Logic.Var

import           Text.PrettyPrint.HughesPJClass ((<+>), Pretty, pPrint)
import qualified Text.PrettyPrint.HughesPJClass as PP

data Form
  = Apply Form Form
  | V Var

  | If Type

  | Not
  | Impl
  | Iff
  | And
  | Or

  | Add Type
  | Mul Type
  | Sub Type
  | Div Type
  | Mod Type

  | Distinct Type
  | Eql Type
  | Lt  Type
  | Le  Type
  | Gt  Type
  | Ge  Type

  | LUnit
  | LBool Bool
  | LInt Integer
  | LReal Double
  deriving (Show, Read, Eq, Ord, Data)

instance Plated Form where plate = uniplate
instance Variadic Form where vars = biplate

app2 :: Form -> Form -> Form -> Form
app2 f x = Apply (Apply f x)

appMany :: Form -> [Form] -> Form
appMany = foldl Apply

mkAnd, mkOr :: Foldable f => f Form -> Form
mkAnd = foldr (app2 And) (LBool True)
mkOr  = foldr (app2 Or) (LBool False)

instance Monoid Form where
  mappend = app2 And
  mempty = LBool True

instance Typed Form where
  typeOf = \case
    V v         -> T.typeOf v
    Apply v _   -> case T.typeOf v of
                     _ :=> t -> t
                     _ -> undefined

    If t        -> T.Bool :=> t :=> t :=> t

    Not         -> T.Bool :=> T.Bool
    Impl        -> T.Bool :=> T.Bool
    Iff         -> T.Bool :=> T.Bool
    And         -> T.Bool :=> T.Bool
    Or          -> T.Bool :=> T.Bool

    Add t       -> t :=> t :=> t
    Mul t       -> t :=> t :=> t
    Sub t       -> t :=> t :=> t
    Div t       -> t :=> t :=> t
    Mod t       -> t :=> t :=> t

    Distinct t  -> T.List t :=> T.Bool
    Eql t       -> t :=> t :=> T.Bool
    Lt t        -> t :=> t :=> T.Bool
    Le t        -> t :=> t :=> T.Bool
    Gt t        -> t :=> t :=> T.Bool
    Ge t        -> t :=> t :=> T.Bool

    LUnit       -> T.Unit
    LBool _     -> T.Bool
    LInt _      -> T.Int
    LReal _     -> T.Real

class Formulaic a where
  toForm :: a -> Form

instance Formulaic Form where
  toForm = id

isLit :: Form -> Bool
isLit = \case
  LUnit   -> True
  LBool _ -> True
  LInt _  -> True
  LReal _ -> True
  _       -> False

isVar :: Form -> Bool
isVar = \case
  V _ -> True
  _   -> False

isBinaryInfix :: Form -> Bool
isBinaryInfix = \case
    And   -> True
    Or    -> True
    Impl  -> True
    Iff   -> True
    Add _ -> True
    Mul _ -> True
    Sub _ -> True
    Div _ -> True
    Mod _ -> True
    Eql _ -> True
    Lt _  -> True
    Le _  -> True
    Gt _  -> True
    Ge _  -> True
    _     -> False

instance Pretty Form where
  pPrint = \case
    Apply (Apply f x) y ->
      if isBinaryInfix f
      then PP.hsep [binArg x, pPrint f, binArg y]
      else PP.parens (inlinePrint f x <+> pPrint y)
    V v          -> PP.pPrint v
    Apply f x    -> PP.parens (pPrint f <+> pPrint x)

    If _         -> PP.text "if"

    Distinct _   -> PP.text "distinct"

    And          -> PP.text "&&"
    Or           -> PP.text "||"
    Impl         -> PP.text "->"
    Iff          -> PP.text "<->"
    Not          -> PP.text "not"

    Add _        -> PP.text "+"
    Mul _        -> PP.text "*"
    Sub _        -> PP.text "-"
    Div _        -> PP.text "/"
    Mod _        -> PP.text "%"

    Eql _        -> PP.text "="
    Lt _         -> PP.text "<"
    Le _         -> PP.text "<="
    Gt _         -> PP.text ">"
    Ge _         -> PP.text ">="

    LUnit         -> PP.text "()"
    LBool b       -> pPrint b
    LInt i        -> pPrint i
    LReal r       -> pPrint r
    where
      binArg f = if isLit f || isVar f then pPrint f else PP.parens (pPrint f)

      inlinePrint f x = case f of
        Apply f' y -> inlinePrint f' y <+> pPrint x
        f' -> pPrint f' <+> pPrint x
