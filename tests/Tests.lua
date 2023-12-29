local logger = require("logger")
-- In Development, so you don't have to wait for all other tests to debug (move to correct location later)
logger.info("running StackRollbackReplayTests")
require("tests.StackRollbackReplayTests")
-- Small tests (unit tests)
logger.info("running PuzzleTests")
require("PuzzleTests")
logger.info("running ServerQueueTests")
require("ServerQueueTests")
logger.info("running StackTests")
require("StackTests")
logger.info("running PanelGenTests")
require("tests.PanelGenTests")
--require("tests.StackGraphicsTests")
logger.info("running JsonEncodingTests")
require("tests.JsonEncodingTests")
logger.info("running NetworkProtocolTests")
require("tests.NetworkProtocolTests")
logger.info("running ThemeTests")
require("tests.ThemeTests")
logger.info("running TouchDataEncodingTests")
require("tests.TouchDataEncodingTests")
logger.info("running utf8AdditionsTests")
require("tests.utf8AdditionsTests")
logger.info("running QueueTests")
require("tests.QueueTests")
-- TimeQueue:update was changed, need to review after finishing up TcpClient
-- require("tests.TimeQueueTests")
logger.info("running tableUtilsTest")
require("tableUtilsTest")
logger.info("running utilTests")
require("utilTests")
--require("AttackFileGenerator") -- TODO: Not really a unit test... generates attack files
-- Medium level tests (integration tests)
logger.info("running TcpClientTests")
require("tests.TcpClientTests")
logger.info("running ReplayTests")
require("tests.ReplayTests")
logger.info("running StackReplayTests")
require("tests.StackReplayTests")
logger.info("running StackTouchReplayTests")
require("tests.StackTouchReplayTests")
logger.info("running GarbageQueueTests")
require("tests.GarbageQueueTests")