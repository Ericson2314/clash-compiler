{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- | Types used in BlackBox modules
module CLaSH.Netlist.BlackBox.Types where

import Data.Text.Lazy       (Text)

-- | A BlackBox Template is a List of Elements
type BlackBoxTemplate = [Element]

-- | Elements of a blackbox context
data Element = C   Text          -- ^ Constant
             | D   Decl          -- ^ Component instantiation hole
             | O                 -- ^ Output hole
             | I   Int           -- ^ Input hole
             | L   Int           -- ^ Literal hole
             | Sym Int           -- ^ Symbol hole
             | Clk (Maybe Int)   -- ^ Clock hole (Maybe clk corresponding to
                                 -- input, clk corresponding to output if Nothing)
             | Rst (Maybe Int)   -- ^ Reset hole
             | Typ (Maybe Int)   -- ^ Type declaration hole
             | TypM (Maybe Int)  -- ^ Type root hole
             | Err (Maybe Int)   -- ^ Error value hole
             | TypElem Element   -- ^ Select element type from a vector type
             | SigD Element (Maybe Int)
  deriving Show

-- | Component instantiation hole. First argument indicates which function argument
-- to instantiate. Second argument corresponds to output and input assignments,
-- where the first element is the output assignment, and the subsequent elements
-- are the consecutive input assignments.
--
-- The LHS of the tuple is the name of the signal, while the RHS of the tuple
-- is the type of the signal
data Decl = Decl Int [(BlackBoxTemplate,BlackBoxTemplate)]
  deriving Show
