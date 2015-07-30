{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE NullaryTypeClasses #-}

module Example53 where

import Data.Map as M
import Data.Maybe as MB
import Data.List as L
import Control.Monad
import Data.Maybe
import GCDerivation
import Example23

{- Example 5.3 -}

-- taking a specific policy dimension
instance WavefrontDimension where
    fl _ =  const True

instance PolicyDimension where
  lr _ o = o == "A"

mp_53 = m_plus al_final "B" prefix_pe
-- 1

mm_53 = m_plus al_final "B" prefix_pe
-- 1

-- The follosing equals to mp_53 - mm_53
m_53 = m al_final (Just "B") prefix_pe
-- 0

