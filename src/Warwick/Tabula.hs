--------------------------------------------------------------------------------
-- Haskell bindings for the University of Warwick APIs                        --
-- Copyright 2019 Michael B. Gale (m.gale@warwick.ac.uk)                      --
--------------------------------------------------------------------------------

module Warwick.Tabula (
    module Warwick.Common,
    module Warwick.Config,
    module Warwick.Tabula.Coursework,
    module Warwick.Tabula.Relationship,

    TabulaInstance(..),

    ModuleCode(..),
    AssignmentID(..),

    TabulaResponse(..),
    TabulaAssignmentResponse(..),

    withTabula,

    retrieveModule,
    retrieveDepartment,

    listAssignments,
    retrieveAssignment,
    listSubmissions,
    postMarks,

    TabulaDownloadCallbacks(..),
    downloadSubmission,
    downloadSubmissionWithCallbacks,

    retrieveMember,
    listRelationships,
    personAssignments,
    listMembers,
    retrieveAttendance,
    
    retrieveTermDates,
    retrieveTermDatesFor,
    retrieveTermWeeks,
    retrieveTermWeeksFor,
    retrieveHolidays
) where

--------------------------------------------------------------------------------

import Control.Monad.Catch (catch, throwM)
import Control.Monad.State
import Control.Monad.Except
--import Control.Monad.Throw

--import Data.Text
import qualified Data.ByteString as BS
import qualified Data.ByteString.Internal as BS
import Data.Text.Encoding (encodeUtf8)
import qualified Data.HashMap.Lazy as HM
import Data.Text (Text, pack)

import Data.Conduit
import Data.Conduit.Binary hiding (mapM_)

import Data.List (intercalate)

import Data.Aeson

import Network.HTTP.Conduit (newManager, tlsManagerSettings)
import Network.HTTP.Simple
import qualified Network.HTTP.Client.Conduit as C

import Servant.API.BasicAuth
import Servant.Client

import Warwick.Config
import Warwick.Common
import Warwick.Tabula.Config
import Warwick.Tabula.Types
import Warwick.Tabula.Coursework
import Warwick.Tabula.Member
import Warwick.Tabula.Payload
import Warwick.Tabula.Relationship
import Warwick.Tabula.MemberSearchFilter
import Warwick.Tabula.API
import qualified Warwick.Tabula.Internal as I
import Warwick.DownloadSubmission

-------------------------------------------------------------------------------

-- | 'withTabula' @instance config action@ runs the computation @action@
-- by connecting to @instance@ with the configuration specified by @config@.
withTabula ::
    TabulaInstance -> APIConfig -> Warwick a -> IO (Either APIError a)
withTabula = withAPI

-------------------------------------------------------------------------------

-- | Client functions generated by servant throw exceptions when a server
-- returns a non-2xx status code. 'handle' @m@ catches exceptions which are
-- thrown when @m@ is executed and tries to convert them into a Tabula response.
handle :: (FromJSON a, HasPayload a)
       => ClientM (TabulaResponse a) -> Warwick (TabulaResponse a)
handle m = lift $ lift $ m `catch` \(e :: ServantError) -> case e of
   FailureResponse r -> case decode (responseBody r) of
       Nothing -> throwM e
       Just r  -> return r
   _                    -> throwM e

-------------------------------------------------------------------------------

-- | `retrieveModule` @code@ retrieves the module identified by @code@.
retrieveModule :: ModuleCode -> Warwick (TabulaResponse Module)
retrieveModule mc = do 
    authData <- getAuthData
    handle $ I.retrieveModule authData mc

-- | `retrieveDepartment` @deptCode@ retrieves information about the 
-- department identified by @deptCode@.
retrieveDepartment :: Text -> Warwick (TabulaResponse Department)
retrieveDepartment dept = do 
    authData <- getAuthData 
    handle $ I.retrieveDepartment authData dept

-------------------------------------------------------------------------------

listAssignments ::
    ModuleCode -> Maybe AcademicYear -> Warwick (TabulaResponse [Assignment])
listAssignments mc yr = do
    authData <- getAuthData
    handle $ I.listAssignments authData mc yr

retrieveAssignment ::
    ModuleCode -> AssignmentID -> [String] -> Warwick (TabulaResponse Assignment)
retrieveAssignment mc aid xs = do
    let fdata = if Prelude.null xs then Nothing else Just (intercalate "," xs)
    authData <- getAuthData
    handle $ I.retrieveAssignment authData mc (unAssignmentID aid) fdata

listSubmissions ::
    ModuleCode -> AssignmentID -> Warwick (TabulaResponse (HM.HashMap String (Maybe Submission)))
listSubmissions mc aid = do
    authData <- getAuthData
    handle $ I.listSubmissions authData mc (unAssignmentID aid)

-- | 'postMarks' @moduleCode assignmentId marks@ uploads the feedback 
-- contained in @marks@ for the assignment identified by @assignmentId@.
postMarks ::
    ModuleCode -> AssignmentID -> Marks -> Warwick (TabulaResponse None)
postMarks mc aid marks = do 
    authData <- getAuthData
    handle $ I.postMarks authData mc (unAssignmentID aid) marks

-------------------------------------------------------------------------------

retrieveMember :: String -> [String] -> Warwick (TabulaResponse Member)
retrieveMember uid fields = do
    let fdata = if Prelude.null fields then Nothing else Just (intercalate "," fields)
    authData <- getAuthData
    handle $ I.retrieveMember authData uid fdata

listRelationships ::
    String -> Warwick (TabulaResponse [Relationship])
listRelationships uid = do
    authData <- getAuthData
    handle $ I.listRelationships authData uid

personAssignments ::
    String -> Maybe AcademicYear -> Warwick TabulaAssignmentResponse
personAssignments uid academicYear = do
    authData <- getAuthData
    lift $ lift $ I.personAssignments authData uid (pack <$> academicYear) `catch` \(e :: ServantError) -> case e of
       FailureResponse r -> case decode (responseBody r) of
           Nothing -> throwM e
           Just r  -> return r
       _                    -> throwM e

-- | `listMembers` @filterSettings offset limit@ 
listMembers ::
    MemberSearchFilter -> Int -> Int -> Warwick (TabulaResponse [Member])
listMembers MemberSearchFilter{..} offset limit = do 
    authData <- getAuthData
    handle $ I.listMembers 
        authData 
        filterDepartment
        (toSearchParam filterFields)
        (Just offset)
        (Just limit) 
        (toSearchParam $ map (pack . show) filterCourseTypes)
        (toSearchParam filterRoutes)
        (toSearchParam filterCourses)
        (toSearchParam filterModesOfAttendance)
        (toSearchParam $ map (pack . show) filterYearsOfStudy)
        (toSearchParam filterLevelCodes)
        (toSearchParam filterSprStatuses)
        (toSearchParam filterModules)
        (toSearchParam filterHallsOfResidence)  

-- | 'retrieveAttendance' @userId academicYear@ retrieves information about
-- the attendance of the user identified by @userId@, limited to
-- the academic year given by @academicYear@.
retrieveAttendance ::
    Text -> AcademicYear -> Warwick (TabulaResponse MemberAttendance)
retrieveAttendance user academicYear = do 
    authData <- getAuthData
    handle $ I.retrieveAttendance authData user (pack academicYear)

-------------------------------------------------------------------------------

-- | `retrieveTermDates` retrieves information about an academic year's terms. 
-- By default, information for the current academic year is returned, but the 
-- academic year can be specified using the `retrieveTermDatesFor` function.
--
-- >>> retrieveTermDates 
-- Right (TabulaOK {tabulaStatus = "ok", tabulaData = [..]})
--
retrieveTermDates :: Warwick (TabulaResponse [Term])
retrieveTermDates = handle I.retrieveTermDates

-- | `retrieveTermDatesFor` @academicYear@ retrieves information about an 
-- academic year's terms. The academic year for which the term dates are
-- retrieved is specified by @academicYear@. This should be the four 
-- character year in which the academic year starts.
--
-- >>> retrieveTermDatesFor "2019"
-- Right (TabulaOK {tabulaStatus = "ok", tabulaData = [..]})
--
retrieveTermDatesFor :: Text -> Warwick (TabulaResponse [Term])
retrieveTermDatesFor academicYear =
    handle $ I.retrieveTermDatesFor academicYear

-- | `retrieveTermWeeks` @numberingSystem@ retrieves information
-- about the weeks in the current academic year. The week's names
-- are determined by the specified @numberingSystem@. If no value
-- is specified, the API defaults to `AcademicNumbering`.
--
-- >>> retrieveTermWeeksFor (Just TermNumbering)
-- Right (TabulaOK {tabulaStatus = "ok", tabulaData = [..]})
--
retrieveTermWeeks :: 
    Maybe NumberingSystem -> Warwick (TabulaResponse [Week])
retrieveTermWeeks numberingSystem =
    handle $ I.retrieveTermWeeks numberingSystem

-- | `retrieveTermWeeksFor` @academicYear numberingSystem@ retrieves 
-- information about the weeks in @academicYear@. The week's names
-- are determined by the specified @numberingSystem@. If no value
-- is specified, the API defaults to `AcademicNumbering`.
--
-- >>> retrieveTermWeeksFor "2019" (Just TermNumbering)
-- Right (TabulaOK {tabulaStatus = "ok", tabulaData = [..]})
--
retrieveTermWeeksFor :: 
    Text -> Maybe NumberingSystem -> Warwick (TabulaResponse [Week])
retrieveTermWeeksFor academicYear numberingSystem =
    handle $ I.retrieveTermWeeksFor academicYear numberingSystem

-- | `retrieveHolidays` retrieves information about holiday dates.
retrieveHolidays :: Warwick (TabulaResponse [Holiday])
retrieveHolidays = handle I.retrieveHolidays 

-------------------------------------------------------------------------------
