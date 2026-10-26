module Main (main) where

import qualified Data.ByteString as B
import Data.Either (isLeft)
import Data.IP (AddrRange, IPv4, IPv6, isMatchedTo)
import Data.List.Split (splitOn)
import qualified Data.Map as Map
import qualified Data.Text as T
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Network.DNS hiding (header)
import Options.Applicative

packStr'' :: String -> B.ByteString
packStr'' = encodeUtf8 . T.pack

unPackStr'' :: B.ByteString -> String
unPackStr'' = T.unpack . decodeUtf8

data Input = Input {resolver :: String, domainList :: FilePath}

parse :: Parser Input
parse = Input <$> argument str (metavar "RESOLVER") <*> argument str (metavar "FILE")

combine :: (Applicative f) => (f a, f b) -> f (a, b)
combine (io_a, io_b) = (,) <$> io_a <*> io_b

match :: ([Bool] -> Bool) -> (a -> b -> Bool) -> [a] -> [b] -> Bool
match merge f as bs = merge (f <$> as <*> bs)

v4sinkRanges :: [AddrRange IPv4]
v4sinkRanges = fmap read ["127.0.0.0/8", "0.0.0.0/8"]

v6sinkRanges :: [AddrRange IPv6]
v6sinkRanges = fmap read ["::1/128", "::/0"]

isBlocked :: (Either DNSError [IPv4], Either DNSError [IPv6]) -> Bool
isBlocked (Left _, Left _) = True
isBlocked (Right v4ips, Right v6ips) = match or isMatchedTo v6ips v6sinkRanges || match or isMatchedTo v4ips v4sinkRanges
isBlocked (Right ips, _) = match or isMatchedTo ips v4sinkRanges
isBlocked (_, Right ips) = match or isMatchedTo ips v6sinkRanges

check :: Input -> IO ()
check (Input resolver domainListFile) = do
  let conf = defaultResolvConf {resolvInfo = RCHostName resolver, resolvCache = Nothing}
  domainListString <- readFile domainListFile
  let domains = filter (\d -> not (null d) && d /= "\r") (splitOn "\n" domainListString)
  rs <- makeResolvSeed conf
  resolved <-
    fmap
      ( (fmap (\(domain, _) -> domain))
          . ( filter
                (\(_, x) -> isBlocked x)
            )
      )
      ( withResolver
          rs
          ( \rslvr ->
              mapM
                ((\domain -> combine (return domain, combine ((lookupA rslvr domain), (lookupAAAA rslvr domain)))) . packStr'')
                domains
          )
      )

  putStr $ unlines (fmap unPackStr'' resolved)

main :: IO ()
main = check =<< execParser opts
  where
    opts =
      info
        (parse <**> helper)
        (progDesc "Check which of the domains specified in a file are blocked by a dns server")
