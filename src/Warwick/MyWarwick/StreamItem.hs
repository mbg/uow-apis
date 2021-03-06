-------------------------------------------------------------------------------
-- Haskell bindings for the University of Warwick APIs                       --
-------------------------------------------------------------------------------
-- This source code is licensed under the MIT licence found in the           --
-- LICENSE file in the root directory of this source tree.                   --
-------------------------------------------------------------------------------

module Warwick.MyWarwick.StreamItem (
    StreamRecipients(..),
    StreamItem(..)
) where 

--------------------------------------------------------------------------------

import Data.Aeson
import Data.Text

--------------------------------------------------------------------------------

-- | Represents the intended recipients for an alert or activity item.
data StreamRecipients = StreamRecipients {
    -- | A list of usernames to send the item to.
    srUsers :: Maybe [Text],
    -- | A list of groups to send the item to.
    srGroups :: Maybe [Text]
} deriving Show

instance ToJSON StreamRecipients where 
    toJSON StreamRecipients{..} = 
        object [ "users" .= srUsers 
               , "groups" .= srGroups 
               ]

-- | Represents an alert or an activity.
data StreamItem = StreamItem {
    -- | A string identifying the type of message.
    siType :: Text,
    -- | The title of the message.
    siTitle :: Text,
    -- | The body of the message.
    siText :: Text,
    -- | Optionally, a URL that the message links to.
    siURL :: Maybe Text,
    -- | The recipients of the message.
    siRecipients :: StreamRecipients
} deriving Show

instance ToJSON StreamItem where 
    toJSON StreamItem{..} = 
        object [ "type" .= siType
               , "title" .= siTitle 
               , "text" .= siText 
               , "url" .= siURL 
               , "recipients" .= siRecipients
               ]

--------------------------------------------------------------------------------
    