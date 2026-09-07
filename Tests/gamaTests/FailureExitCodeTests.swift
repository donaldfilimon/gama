import GamaCore
import Testing

/// Public construction path for process-facing failure codes. These pin
/// the additive `FailureExitCode` / `failure(exitCode:_:)` surface without
/// `@testable`, so a missing public declaration fails the same way a
/// consumer would.
@Suite("Validated failure exit codes")
struct FailureExitCodeTests {
    @Test(
        "construction fails for zero, negatives, and values above 255",
        arguments: [Int32(0), -1, .min, 256, .max]
    )
    func rejectsOutOfRange(_ raw: Int32) {
        #expect(FailureExitCode(rawValue: raw) == nil)
    }

    @Test(
        "every code in 1...255 constructs and yields a failing status",
        arguments: Int32(1)...Int32(255)
    )
    func acceptsNonzeroByte(_ raw: Int32) throws {
        let code = try #require(FailureExitCode(rawValue: raw))
        #expect(code.rawValue == raw)
        let status = CompletionStatus.failure(exitCode: code)
        #expect(status.code == raw)
        #expect(status.isSuccess == false)
    }

    @Test("general failure is raw value 1")
    func generalFailureIsOne() {
        #expect(FailureExitCode.general.rawValue == 1)
    }

    @Test("handbook example starts as code 1 and not success")
    func handbookExample() {
        let status = CompletionStatus.failure(
            exitCode: .general,
            "The report could not be written"
        )
        #expect(status.code == 1)
        #expect(status.isSuccess == false)
        #expect(status.message == "The report could not be written")
    }

    @Test("failure(exitCode:_:) preserves a diagnostic message")
    func preservesMessage() {
        let status = CompletionStatus.failure(
            exitCode: .general,
            "Unable to write output"
        )
        #expect(status.code == 1)
        #expect(status.message == "Unable to write output")
        #expect(status.isSuccess == false)
    }

    @Test("failure(exitCode:) defaults the message to nil")
    func defaultMessageIsNil() {
        #expect(CompletionStatus.failure(exitCode: .general).message == nil)
    }

    @Test("FailureExitCode is RawRepresentable and Hashable")
    func supportsRawRepresentableAndHashable() throws {
        let one = try #require(FailureExitCode(rawValue: 1))
        let two = try #require(FailureExitCode(rawValue: 2))
        #expect(Set([one, one, two]).count == 2)
        func raw<T: RawRepresentable>(_ code: T) -> T.RawValue { code.rawValue }
        #expect(raw(two) == 2)
    }

    @Test("a Sendable FailureExitCode crosses an actor boundary")
    func sendableValueCrossesActorBoundary() async {
        actor Receiver {
            func accept(_ code: FailureExitCode) -> Int32 { code.rawValue }
        }
        let value = await Receiver().accept(.general)
        #expect(value == 1)
    }

    @Test("legacy failure(code: 0) still reports success")
    func legacyZeroFactoryRemainsUnchanged() {
        let status = CompletionStatus.failure(code: 0, "Legacy contract")
        #expect(status.isSuccess)
        #expect(status.message == "Legacy contract")
    }

    @Test("legacy failure(code:) still accepts a negative code")
    func legacyNegativeFactoryRemainsUnchanged() {
        #expect(CompletionStatus.failure(code: -42).code == -42)
    }

    @Test("code stays mutable and the raw initializer still accepts 256")
    func legacyInitializerAndMutabilityRemainUnchanged() {
        var status = CompletionStatus.failure(exitCode: .general)
        status.code = 0
        #expect(status.isSuccess)
        #expect(CompletionStatus(code: 256).code == 256)
    }

    @Test("ordinary success remains code zero")
    func ordinarySuccessIsUnaffected() {
        #expect(CompletionStatus.success.code == 0)
        #expect(CompletionStatus.success.isSuccess)
    }
}
