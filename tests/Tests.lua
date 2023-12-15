-- In Development, so you don't have to wait for all other tests to debug (move to correct location later)
require("tests.TcpClientTests")
-- Small tests (unit tests)
require("PuzzleTests")
require("ServerQueueTests")
require("StackTests")
require("tests.PanelGenTests")
--require("tests.StackGraphicsTests")
require("tests.JsonEncodingTests")
require("tests.NetworkProtocolTests")
require("tests.ThemeTests")
require("tests.TouchDataEncodingTests")
require("tests.utf8AdditionsTests")
require("tests.QueueTests")
-- TimeQueue:update was changed, need to review after finishing up TcpClient
-- require("tests.TimeQueueTests")
require("tableUtilsTest")
require("utilTests")
--require("AttackFileGenerator") -- TODO: Not really a unit test... generates attack files
-- Medium level tests (integration tests)
require("tests.ReplayTests")
require("tests.StackReplayTests")
require("tests.StackRollbackReplayTests")
require("tests.StackTouchReplayTests")
require("tests.GarbageQueueTests")