{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE NullaryTypeClasses #-}

module GCDerivation where

import Data.Map as M
import Data.List as L
import Control.Monad
import Data.Maybe

{-----------------------------------------------------------------}
{--                   Basic definitions                         --}
{-----------------------------------------------------------------}

type FName = String
type ObjId = String
type k :-> v = M.Map k v

-- An object is represented by its id (Int) and a list of objects ids,
-- to which it points with its fields (String :-> Int)
data Object = O {
  objid :: ObjId,
  fields :: FName :-> (Maybe ObjId)
} deriving (Eq, Ord, Show)

type ObjectOrNull = Maybe Object
type Ref = Maybe ObjId
type AL = [Object]

-- Mapping fields to allocated values
-- The parameter AL is always passed as list 
h :: AL -> ObjId -> FName -> ObjectOrNull
h als oid fname = do
  -- Find the object by id "oid"
  o <- L.find (\ob -> objid ob == oid) als 
  -- Find the object ID or Nothing for the field name "fname"
  fObjId <- join $ M.lookup fname $ fields o
  -- Find the object for the id "fObjId"
  L.find (\ob -> objid ob == fObjId) als

-- An alias
obj_f = h
pre k = take k

data ActionKind = T | M | A deriving (Eq, Ord, Show)
data LogEntry = LE {
  kind    :: ActionKind,
  source  :: ObjId,
  field   :: FName,
  old     :: Ref,
  new     :: Ref
} deriving (Eq, Ord, Show)
  
type Log = [LogEntry]

fields' = toList . fields

-- Definition of the wavefront
wavefront :: Log -> [(ObjId, FName)]
wavefront p = [(source pi, field pi) | pi <- p, kind pi == T]

-- Definition of behind/ahead
behind p (o, f) = elem (o, f) $ wavefront p
ahead p = not . (behind p)

-- util function for mapping a list of Maybe-objects to their IDs
ids :: [ObjectOrNull] -> [ObjId]
ids ons = [objid o | Just o <- ons]

{-----------------------------------------------------------------}
{--     The initial expose function of the apex algorithm       --}
{-----------------------------------------------------------------}

-- The initial expose_apex function
-- for giving the reachable object

expose_apex :: AL -> [LogEntry] -> [ObjId]
expose_apex als p = ids $ nub $ 
 [obj_f als o f |
  i <- [0 .. length p - 1],
  let pi = p !! i
      o = source pi
      f = field pi
      prepi = pre i p,
  elem (kind pi) [M, A],
  elem (o, f) $ wavefront prepi]

{-----------------------------------------------------------------}
{-- Implementing different partitions over the precision axes   --}
{-----------------------------------------------------------------}

-- So far, we are representing partitions via boolean selector functions

{--------------------------------}
{- 5.1: The Wavefront Dimension -}
{--------------------------------}

class WavefrontDimension where
  fl, ol :: [Object] -> ObjId -> Bool
  fl als = not . (ol als)
  ol als = not . (fl als)

-- All fields of all objects ever
all_fields :: [Object] -> [FName]
all_fields als = [fname | o <- als, fname <- keys $ fields o]

{- two views to the wavefront -}
wgt, wlt :: WavefrontDimension => [Object] -> Log -> [(ObjId, FName)]

{- 

The second component of the concatenation iterates over all available
fields f' of the allocated objects and all objects o in the
wavefront, pairing them and returning the combinations.

-}

-- util function for getting all fields of an object by id
obj_fields :: [Object] -> ObjId -> [FName]
obj_fields als id = 
 let tmp = do o <- L.find (\ob -> objid ob == id) als
              return $ keys $ fields o
 in case tmp of Just fs -> fs; _ -> []
           

wgt als p =
  let wf = wavefront p in
  nub $ [(o, f) | (o, f) <- wf, fl als o] 
        ++
        [(o, f) | (o, f') <- wf, -- *some* o's field is in wf
                  f <- obj_fields als o, 
                  ol als o]

{- 

Check, whether the following reading of the quantifiers is accurate:
essentially, the second component of the concatenation iterates over
all available fields f' of the allocated objects and all objects o in
the wavefront. It then checks whether the pair (o, f') belongs to the
wavefront wf, and in this case returns pairing of this object with all
possible fields.

-}

all_fields_in_wf als o wf = 
  let ofs = obj_fields als o
      wfs = [f | (o', f) <- wf, o' == o]   
  in  (sort ofs) == (sort wfs)

wlt als p =
  let wf = wavefront p
      fs = all_fields als in
  nub $ [(o, f) | (o, f)  <- wf, fl als o] ++
        [(o, f) | (o, f) <- wf, 
                  -- *all* o's fields are in the wf                  
                  all_fields_in_wf als o wf,
                  elem f $ obj_fields als o,
                  ol als o]

-- {-----------------------------------------------------}
-- {-   5.2, 5.4: The Policy and Protection Dimensions  -}
-- {-----------------------------------------------------}

class PolicyDimension where
  sr, lr :: [Object] -> ObjId -> Bool
  sr als = not . (lr als)
  lr als = not . (sr als)

class ProtectionDimension where
  is, ds :: ObjectOrNull -> Bool
  is o = (not $ isNothing o) && (not $ ds o)
  ds o = (not $ isNothing o) && (not $ is o)

deref :: [Object] -> Ref -> ObjectOrNull
deref als ref = do
  r <- ref
  L.find (\o -> objid o == r) als

-- expose_r from Section 5.2.1
expose_r :: (WavefrontDimension, ProtectionDimension, PolicyDimension) =>
         AL -> [LogEntry] -> [ObjectOrNull]
expose_r als p = nub $ [obj_f als o f |
  i <- [0 .. length p - 1],
  let pi = p !! i
      o = source pi
      f = field pi
      prepi = pre i p,
  elem (kind pi) [M, A],
  elem (o, f) $ wgt als prepi,
  sr als o,
  is $ deref als $ new pi,
  is $ obj_f als o f]

-- 5.2.2: Cross-wavefront counts

m_plus, m_minus :: (WavefrontDimension, PolicyDimension) =>
                   AL -> Object -> Log -> Int

m_plus als o p = length $ [pi |
  i <- [0 .. length p - 1],
  let pi = p !! i
      prepi = pre i p,
  elem (kind pi) [M, A],
  (deref als $ new pi) == Just o,
  elem (source pi, field pi) $ wgt als prepi,
  lr als $ source pi]

m_minus als o p = length $ [pi |
  i <- [0 .. length p - 1],
  let pi = p !! i
      prepi = pre i p,
  elem (kind pi) [M, A],
  (deref als $ new pi) == Just o,
  elem (source pi, field pi) $ wlt als prepi,
  lr als $ source pi]

m :: (WavefrontDimension, PolicyDimension) =>
     AL -> ObjectOrNull -> Log -> Int
m als on p = case on of
 Just o -> m_plus als o p - m_minus als o p
 Nothing -> 0

-- Collection by counting
expose_c :: (WavefrontDimension, ProtectionDimension, PolicyDimension) =>
         AL -> [LogEntry] -> [ObjectOrNull]
expose_c als p = nub $ [n |
  i <- [0 .. length p - 1],
  let pi = p !! i
      n  = deref als $ new pi,
  m als n p > 0, is n]


expose_rc :: (WavefrontDimension, ProtectionDimension, PolicyDimension) =>
         AL -> [LogEntry] -> [ObjectOrNull]
expose_rc als p = nub $ expose_r als p ++ expose_c als p


{-----------------------------------------------------}
{-            5.3: The Threshold Dimensions          -}
{-----------------------------------------------------}

data I = Inf | Ind Int deriving (Eq, Ord, Show)

-- This is relevant for the mutator, not the collector
class ThresholdDimension where
  dt :: I -> [Object] -> ObjId -> Bool
  dt i = case i of Ind j -> dk j ; _ -> dinf

  dinf :: [Object] -> ObjId -> Bool
  dk   :: Int -> [Object] -> ObjId -> Bool

{-----------------------------------------------------}
{-        5.4: Protection Dimension (contd.)         -}
{-----------------------------------------------------}

expose_d :: (WavefrontDimension, ProtectionDimension, PolicyDimension) =>
         AL -> [LogEntry] -> [ObjectOrNull]
expose_d als p = nub $ [o |
  i <- [0 .. length p - 1],
  let pi = p !! i
      o  = deref als $ old pi
      prepi = pre i p,
  not $ elem (source pi, field pi) $ wlt als prepi,
  ds o]

-- Final version of the expose function

expose_rcd :: (WavefrontDimension, ProtectionDimension, PolicyDimension) =>
              AL -> [LogEntry] -> [ObjectOrNull]
expose_rcd als p = nub $ expose_rc als p ++ expose_d als p

{-----------------------------------------------------------------}
{--                    The  examples from the paper             --}
{-----------------------------------------------------------------}

{- Example 2.3 -}

-- Initial objects
r1, a, b, c, d, e :: Object
r1 = O "r1" $ fromList $ 
              [("f1", Nothing), ("f2", Just "A"), ("f3", Just "E")]
a  = O "A" $ fromList $ 
             [("f1", Nothing), ("f2", Nothing), ("f3", Nothing)]
b = O "B" empty
c = O "C" $ fromList [("f", Just "B")]
d = O "D" $ fromList [("f", Just "E")]
e = O "E" empty

-- Final set of the objects
al_final = [r1, a, b, c, d, e]

prefix_pe :: [LogEntry]
prefix_pe = [
  LE T "r1" "f2" (Just "A") (Just "A"),
  LE T "A"  "f1" Nothing    Nothing,
  LE T "r1" "f3" Nothing    Nothing,
  --
  LE M "r1" "f1" Nothing    (Just "B"),
  LE M "A"  "f1" Nothing    (Just "B"),
  LE M "r1" "f3" Nothing    (Just "E"),
  --
  LE M "A"  "f2" (Just "C")  Nothing,
  LE M "r1" "f1" (Just "B")  Nothing,
  LE T "A"  "f2" Nothing     Nothing,
  --
  LE T "r1" "f1" Nothing    Nothing,
  LE M "A"  "f3" (Just "D") Nothing,
  LE M "A"  "f1" (Just "B") Nothing,
  --
  LE T "A"  "f3" Nothing    Nothing]

-- Computing the wavefront

wf_pe :: [(ObjId, FName)]
wf_pe = wavefront prefix_pe 
-- try wf_pre from the interpreter
-- Okay, that works!

{- Example 3.1 -}
ex_apex_res :: [ObjId]
ex_apex_res = expose_apex al_final prefix_pe 
-- OK, that works too




-- TODO: examples from the rest of the paper