{-# LANGUAGE TemplateHaskell #-}
module Logic.Formula where

import           Control.Lens

import           Data.Data (Data)
import           Data.Data.Lens (uniplate)
import           Data.List (sort)
import           Data.Text.Prettyprint.Doc

import           Logic.Type (Type((:=>)), Typed)
import qualified Logic.Type as T
import           Logic.Var

data Form
  = Form :@ Form
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

  | Store Type Type
  | Select Type Type

  | LUnit
  | LBool Bool
  | LInt Integer
  | LReal Double
  deriving (Show, Read, Eq, Ord, Data)

infixl 9 :@

makePrisms ''Form

instance Plated Form where plate = uniplate

instance Monoid Form where
  mappend = mkAnd
  mempty = LBool True

instance Typed Form where
  typeOf = \case
    V v         -> T.typeOf v
    v :@ _      -> case T.typeOf v of
                     _ :=> t -> t
                     _ -> error "bad function application type"

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

    Select t t' -> T.Array t t' :=> t :=> t' :=> T.Array t t'
    Store t t'  -> T.Array t t' :=> t :=> t'

    LUnit       -> T.Unit
    LBool _     -> T.Bool
    LInt _      -> T.Int
    LReal _     -> T.Real

instance Pretty Form where
  pretty = \case
    f :@ x :@ y ->
      if isBinaryInfix f
      then hsep [binArg x, pretty f, binArg y]
      else parens (inlinePrint f x <+> pretty y)
    V v          -> pretty v
    f :@ x       -> parens (pretty f <+> pretty x)

    If _         -> pretty "if"

    Distinct _   -> pretty "distinct"

    And          -> pretty "&&"
    Or           -> pretty "||"
    Impl         -> pretty "->"
    Iff          -> pretty "<->"
    Not          -> pretty "not"

    Add _        -> pretty "+"
    Mul _        -> pretty "*"
    Sub _        -> pretty "-"
    Div _        -> pretty "/"
    Mod _        -> pretty "%"

    Eql _        -> pretty "="
    Lt _         -> pretty "<"
    Le _         -> pretty "<="
    Gt _         -> pretty ">"
    Ge _         -> pretty ">="

    Store{}      -> pretty "store"
    Select{}     -> pretty "select"

    LUnit        -> pretty "()"
    LBool b      -> pretty b
    LInt i       -> pretty i
    LReal r      -> pretty r
    where
      binArg f = if isLit f || isVar f then pretty f else parens (pretty f)

      inlinePrint f x = case f of
        f' :@ y -> inlinePrint f' y <+> pretty x
        f' -> pretty f' <+> pretty x

class Formulaic a where
  toForm :: a -> Form

instance Formulaic Form where
  toForm = id

-- | Apply a function to two arguments.
app2 :: Form -> Form -> Form -> Form
app2 f x y = f :@ x :@ y

app3 :: Form -> Form -> Form -> Form -> Form
app3 f x y z = f :@ x :@ y :@ z

appMany :: Form -> [Form] -> Form
appMany = foldl (:@)

mkAnd :: Form -> Form -> Form
mkAnd x y
  | x == LBool True = y
  | y == LBool True = x
  | x == y          = x
  | otherwise       = app2 And x y

mkOr :: Form -> Form -> Form
mkOr x y
  | x == LBool False = y
  | y == LBool False = x
  | x == y           = x
  | otherwise        = app2 Or x y

mkEql :: Type -> Form -> Form -> Form
mkEql t x y
  | x == y = LBool True
  | otherwise = let [x', y'] = sort [x, y] in app2 (Eql t) x' y'

manyAnd, manyOr :: Foldable f => f Form -> Form
manyAnd = foldr mkAnd (LBool True)
manyOr  = foldr mkOr (LBool False)

-- | Is the formula a literal?
isLit :: Form -> Bool
isLit = \case
  LUnit   -> True
  LBool _ -> True
  LInt _  -> True
  LReal _ -> True
  _       -> False

-- | Is the formula simply a variable?
isVar :: Form -> Bool
isVar = \case
  V _ -> True
  _   -> False

-- | Is the formula an infix operator?
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
