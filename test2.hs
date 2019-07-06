{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}

import           Data.Kind                      ( Constraint )
import           Data.Function                  ( on )
import           Data.Functor.Compose           ( Compose(Compose)
                                                , getCompose
                                                )
import           Control.Arrow ((&&&))


data SemigroupD a = SemigroupD {
  (.<>) :: a -> a -> a
  }

data MonoidD a = MonoidD {
    memptyD  :: a
  }

data EqD a = EqD {
  (.==) :: a -> a -> Bool
  }

data OrdD a = OrdD {
    (.<)  :: a -> a -> Bool
  --- vv bit of a wart that we have to have this.  We need it to
  --- implement Preserves.
  , (..==) :: a -> a -> Bool
  }

data FunctorD f = FunctorD {
  fmapD :: forall a b. (a -> b) -> f a -> f b
  }

data ApplicativeD f = ApplicativeD {
    pureD   :: forall a. a -> f a
  , (.<*>)  :: forall a b. f (a -> b) -> f a -> f b
  , liftA2D :: forall a b c. (a -> b -> c) -> f a -> f b -> f c
  }

type instance Subclasses SemigroupD a = ()
type instance Subclasses MonoidD a = Class SemigroupD a
type instance Subclasses EqD a = ()
type instance Subclasses OrdD a = Class EqD a
type instance Subclasses FunctorD f = ()
type instance Subclasses ApplicativeD f = Class FunctorD f

instance Preserves Either EqD where
  preserve e1 e2 = EqD { (.==) = \a b ->
                           case (a, b) of
                             (Left l1, Left l2) -> (.==) e1 l1 l2
                             (Right r1, Right r2) -> (.==) e2 r1 r2
                             (Left _, Right _) -> False
                             (Right _, Left _) -> False
                       }

instance Preserves (,) EqD where
  preserve e1 e2 = EqD { (.==) = \(a1,a2) (b1,b2) ->
                           (.==) e1 a1 b1 && (.==) e2 a2 b2 }

instance Preserves Either OrdD where
  preserve e1 e2 = OrdD { (.<) = \a b ->
                            case (a, b) of
                              (Left l1, Left l2) -> (.<) e1 l1 l2
                              (Right r1, Right r2) -> (.<) e2 r1 r2
                              (Left _, Right _) -> True
                              (Right _, Left _) -> False
                        , (..==) = \a b ->
                           case (a, b) of
                             (Left l1, Left l2) -> (..==) e1 l1 l2
                             (Right r1, Right r2) -> (..==) e2 r1 r2
                             (Left _, Right _) -> False
                             (Right _, Left _) -> False
                        }

instance Preserves (,) OrdD where
  preserve e1 e2 = OrdD { (.<) = \(a1,a2) (b1,b2) ->
                            (.<) e1 a1 b1
                            || ((..==) e1 a1 b1 && (.<) e2 a2 b2)
                        , (..==) = \(a1,a2) (b1,b2) ->
                           (..==) e1 a1 b1 && (..==) e2 a2 b2
                        }

instance Preserves (,) SemigroupD where
  preserve m1 m2 = SemigroupD { (.<>) = \(a1,a2) (b1,b2) ->
                                  ((.<>) m1 a1 b1, (.<>) m2 a2 b2) }

instance Preserves (,) MonoidD where
  preserve s1 s2 = MonoidD { memptyD = (memptyD s1, memptyD s2) }


instance Preserves Compose FunctorD where
  preserve f1 f2 =
    FunctorD { fmapD = \f c -> Compose ((fmapD f1 . fmapD f2) f (getCompose c)) }

instance Preserves Compose ApplicativeD where
  preserve f1 f2 =
    ApplicativeD { pureD  = Compose . pureD f1 . pureD f2
                 , (.<*>) = \(Compose f) (Compose x) ->
                     Compose (liftA2D f1 ((.<*>) f2) f x)
                 , liftA2D = \f (Compose x) (Compose y) ->
                     Compose (liftA2D f1 (liftA2D f2 f) x y)
                 }

instance (Class EqD a, Class EqD b) => Class EqD (Either a b) where
  methods = preserveClass

instance (Class EqD a, Class EqD b) => Class EqD (a, b) where
  methods = preserveClass

instance (Class SemigroupD a, Class SemigroupD b) => Class SemigroupD (a, b) where
  methods = preserveClass

instance (Class MonoidD a, Class MonoidD b) => Class MonoidD (a, b) where
  methods = preserveClass

instance (Class FunctorD f, Class FunctorD g)
  => Class FunctorD (Compose f g) where
  methods = preserveClass

instance (Class ApplicativeD f, Class ApplicativeD g)
  => Class ApplicativeD (Compose f g) where
  methods = preserveClass

data Foo a = Foo { foo :: Maybe a, bar :: [Int] }

-- "Derived by compiler"
deriveForFoo :: (Class f [Int], Class f (Maybe a), Preserves (,) f, Invariant f)
             => f (Foo a)
deriveForFoo = mapInvariant (uncurry Foo) (foo &&& bar) (preserve methods methods)

instance Class EqD a => Class EqD (Foo a) where
  methods = deriveForFoo

instance Class SemigroupD a => Class MonoidD (Maybe a) where
  methods = MonoidD { memptyD = Nothing }

instance Class SemigroupD a => Class SemigroupD (Foo a) where
  methods = deriveForFoo

instance Class MonoidD a => Class MonoidD (Foo a) where
  methods = deriveForFoo

-- { Library

preserveClass :: (Preserves f d, Class d a, Class d b) => (d (f a b))
preserveClass = preserve methods methods

type family Subclasses (f :: k -> *) (a :: k) :: Constraint

class Subclasses f a => Class (f :: k -> *) (a :: k) where
  methods :: f a

class Invariant f where
  mapInvariant :: (a -> b) -> (b -> a) -> f a -> f b

class Preserves p f where
  preserve :: f a -> f b -> f (p a b)

(.:) f g a b = f (g a b)

-- }

-- { Standard library

instance Class EqD Int where
  methods = EqD { (.==) = (==) }

instance Class EqD a => Class EqD [a] where
  methods = EqD { (.==) = let
                   (.===) = \a b ->
                     case (a, b) of
                       ([],[]) -> True
                       (a':as, b':bs) -> (.==) methods a' b' && (.===) as bs
                   in (.===)
               }

instance Class EqD a => Class EqD (Maybe a) where
  methods = EqD { (.==) = \a b ->
                     case (a, b) of
                       (Nothing, Nothing) -> True
                       (Just a', Just b') -> (.==) methods a' b'
               }

instance Class SemigroupD [a] where
  methods = SemigroupD { (.<>) = (++) }

instance Class MonoidD [a] where
  methods = MonoidD { memptyD = [] }

instance Class SemigroupD a => Class SemigroupD (Maybe a) where
  methods = SemigroupD { (.<>) = \a b -> case (a, b) of
                          (Nothing, Nothing) -> Nothing
                          (Nothing, Just b)  -> Just b
                          (Just a, Nothing)  -> Just a
                          (Just a, Just b)   -> Just ((.<>) methods a b)
                          }

-- }

-- { Not used at the moment

instance Invariant EqD where
  mapInvariant _ g e = EqD { (.==) = (.==) e `on` g }

instance Invariant OrdD where
  mapInvariant _ g e = OrdD { (.<) = (.<) e `on` g
                            , (..==) = (..==) e `on` g
                            }

instance Invariant SemigroupD where
  mapInvariant f g s =
    SemigroupD { (.<>) = f .: ((.<>) s `on` g) }

instance Invariant MonoidD where
  mapInvariant f _ m = MonoidD { memptyD = f (memptyD m) }

-- }

