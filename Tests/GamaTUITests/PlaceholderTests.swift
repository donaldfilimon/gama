import Testing
@testable import GamaTUI

@Suite
struct PlaceholderTests {
    @Test func keyParserExists() {
        _ = KeyParser()
    }
}
