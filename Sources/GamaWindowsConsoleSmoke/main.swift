#if os(Windows)
import GamaTUI
import WinSDK

var allocated = false
var input = GetStdHandle(STD_INPUT_HANDLE)
var output = GetStdHandle(STD_OUTPUT_HANDLE)
var originalInput: DWORD = 0
var originalOutput: DWORD = 0
if !GetConsoleMode(input, &originalInput) || !GetConsoleMode(output, &originalOutput) {
    // CI hosts may attach a console while redirecting this process's standard
    // handles to pipes. Detach before allocating the private console whose
    // mode transitions this executable verifies.
    _ = FreeConsole()
    guard AllocConsole() else { fatalError("AllocConsole failed") }
    allocated = true
    input = GetStdHandle(STD_INPUT_HANDLE)
    output = GetStdHandle(STD_OUTPUT_HANDLE)
    guard GetConsoleMode(input, &originalInput), GetConsoleMode(output, &originalOutput) else {
        fatalError("allocated console modes unavailable")
    }
}
let originalCodePage = GetConsoleOutputCP()
var terminal = Terminal()
try terminal.enterRawMode()
try terminal.exitRawModeChecked()
var restoredInput: DWORD = 0
var restoredOutput: DWORD = 0
guard GetConsoleMode(input, &restoredInput), GetConsoleMode(output, &restoredOutput),
    restoredInput == originalInput, restoredOutput == originalOutput,
    GetConsoleOutputCP() == originalCodePage
else { fatalError("console mode/code-page restoration mismatch") }
if allocated { _ = FreeConsole() }
print("OK — native Windows console raw mode, UTF-8/VT setup, and restoration")
#else
print("gama-windows-console-smoke is a native Windows acceptance executable")
#endif
