{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module AEADProperties (
  testAEAD
  ) where

import           Util
import           Crypto.Saltine.Core.AEAD
import           Crypto.Saltine.Class (decode,encode)
import           Crypto.Saltine.Internal.ByteSizes as Bytes

import           Control.Applicative
import qualified Data.ByteString                      as S
import           Test.Framework.Providers.QuickCheck2
import           Test.Framework
import           Test.QuickCheck (Property, (==>))
import           Test.QuickCheck.Arbitrary

instance Arbitrary Nonce where
    arbitrary =
        do bs <- S.pack <$> vector Bytes.secretBoxNonce
           maybe (fail "impossible arbitrary failure.") pure (decode bs)

instance Arbitrary Key where
    arbitrary =
        do bs <- S.pack <$> vector Bytes.secretBoxKey
           maybe (fail "impossible arbitrary failure.") pure (decode bs)

instance Show Key where
    show = show . encode
instance Show Nonce where
    show = show . encode

-- | Ciphertext can be decrypted
rightInverseProp :: Key -> Nonce -> Message -> Message -> Bool
rightInverseProp k n (Message bs) (Message aad) =
  Just bs == aeadOpen k n (aead k n bs aad) aad

-- | Detached ciphertext/tag can be decrypted
rightInverseDetachedProp :: Key -> Nonce -> Message -> Message -> Bool
rightInverseDetachedProp k n (Message bs) (Message aad) =
  let (tag,ct) = aeadDetached k n bs aad
  in Just bs == aeadOpenDetached k n tag ct aad

-- | Ciphertext cannot be decrypted if the ciphertext is perturbed
rightInverseFailureProp :: Key -> Nonce -> Message -> Message -> Perturb -> Property
rightInverseFailureProp k n (Message bs) (Message aad) p =
  S.length bs /= 0 ==>
   let ct = aead k n bs aad
       fakeCT = perturb ct p
   in fakeCT /= ct ==> Nothing == aeadOpen k n fakeCT aad

-- | Ciphertext cannot be decrypted if the aad is perturbed
rightInverseAADFailureProp :: Key -> Nonce -> Message -> Message -> Message -> Property
rightInverseAADFailureProp k n (Message bs) (Message aad) (Message aad2) =
  aad /= aad2 ==> Nothing == aeadOpen k n (aead k n bs aad) aad2

-- | Ciphertext cannot be decrypted if the tag is perturbed
rightInverseTagFailureProp :: Key -> Nonce -> Message -> Message -> Message -> Property
rightInverseTagFailureProp k n (Message bs) (Message aad) (Message newTag) =
   let (tag,ct) = aeadDetached k n bs aad
   in newTag /= tag ==> Nothing == aeadOpenDetached k n newTag ct aad

-- | Ciphertext cannot be decrypted if the ciphertext is perturbed
rightInverseFailureDetachedProp :: Key -> Nonce -> Message -> Message -> Perturb -> Property
rightInverseFailureDetachedProp k n (Message bs) (Message aad) p@(Perturb pBytes) =
  let (tag,ct) = aeadDetached k n bs aad
  in S.length bs > length pBytes ==>
        Nothing == aeadOpenDetached k n tag (perturb ct p) aad

-- | Ciphertext cannot be decrypted with a different key
cannotDecryptKeyProp :: Key -> Key -> Nonce -> Message -> Message -> Property
cannotDecryptKeyProp k1 k2 n (Message bs) (Message aad) =
  let ct = aead k1 n bs aad
  in k1 /= k2 ==> Nothing == aeadOpen k2 n ct aad

-- | Ciphertext cannot be decrypted with a different key
cannotDecryptKeyDetachedProp :: Key -> Key -> Nonce -> Message -> Message -> Property
cannotDecryptKeyDetachedProp k1 k2 n (Message bs) (Message aad) =
  let (tag,ct) = aeadDetached k1 n bs aad
  in k1 /= k2 ==> Nothing == aeadOpenDetached k2 n tag ct aad

-- | Ciphertext cannot be decrypted with a different nonce
cannotDecryptNonceProp :: Key -> Nonce -> Nonce -> Message -> Message -> Property
cannotDecryptNonceProp k n1 n2 (Message bs) (Message aad) =
  n1 /= n2 ==> Nothing == aeadOpen k n2 (aead k n1 bs aad) aad

-- | Ciphertext cannot be decrypted with a different nonce
cannotDecryptNonceDetachedProp :: Key -> Nonce -> Nonce -> Message -> Message -> Property
cannotDecryptNonceDetachedProp k n1 n2 (Message bs) (Message aad) =
  let (tag,ct) = aeadDetached k n1 bs aad
  in n1 /= n2 ==> Nothing == aeadOpenDetached k n2 tag ct aad

testAEAD :: Test
testAEAD = buildTest $ do

  return $ testGroup "...Internal.AEAD" [

    testProperty "Can decrypt ciphertext"
    $ rightInverseProp,

    testProperty "Can decrypt ciphertext (detached)"
    $ rightInverseDetachedProp,

    testGroup "Cannot decrypt ciphertext when..." [

      testProperty "... ciphertext is perturbed"
      $ rightInverseFailureProp,

      testProperty "... AAD is perturbed"
      $ rightInverseAADFailureProp,

      testProperty "... ciphertext is perturbed (detached)"
      $ rightInverseFailureDetachedProp,

      testProperty "... tag is perturbed (detached)"
      $ rightInverseTagFailureProp,

      testProperty "... using the wrong key"
      $ cannotDecryptKeyProp,

      testProperty "... using the wrong key (detached)"
      $ cannotDecryptKeyDetachedProp,

      testProperty "... using the wrong nonce"
      $ cannotDecryptNonceProp,

      testProperty "... using the wrong nonce (detached"
      $ cannotDecryptNonceDetachedProp

      ]
    ]
