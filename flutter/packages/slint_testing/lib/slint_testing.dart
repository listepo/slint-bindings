/// Test Slint UIs through the accessibility tree.
///
/// Instantiates a `.slint` component on Slint's testing backend
/// (`i-slint-backend-testing`) — no window, no rendering, no event loop — and
/// exposes it as elements you can find by label, id, type, or role, then
/// click, fill in, and assert on. See [SlintTestApp].
library;

export 'src/element_info.dart' show SlintElementInfo;
export 'src/testing.dart' show SlintElement, SlintTestApp, SlintTestException;
