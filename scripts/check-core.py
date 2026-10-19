#!/usr/bin/env python3
"""Run existing core regression cases without XCTest on Command Line Tools hosts.

This explicit standalone runner adapts the checked-in assertion calls. It does
not supply an XCTest module or claim to execute the XCTest framework.
"""
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / 'Tests/ChemCraftCoreTests/ParserTests.swift').read_text()
cases = re.findall(r'func (test\w+)\(\)(\s+throws)?\s*\{', source)
if not cases:
    raise SystemExit('No supported core regression cases found')
source = source.replace('import XCTest', '').replace('@testable import ChemCraftCore', '')
source = source.replace('ParserTests: XCTestCase', 'ParserTests')
source = source.replace('XCTAssertEqual', 'expectEqual').replace('XCTAssertTrue', 'expectTrue')
if re.search(r'\bXCT\w+', source):
    raise SystemExit('Unsupported XCTest feature; run swift test using full Xcode')
helpers = r'''
import Foundation
var failures = 0
func recordFailure(_ message: String, _ file: StaticString, _ line: UInt) {
    failures += 1
    fputs("FAIL \(file):\(line): \(message)\n", stderr)
}
func expectEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try lhs(), b = try rhs(); if a != b { recordFailure("\(a) != \(b)", file, line) } }
    catch { recordFailure(String(describing: error), file, line) }
}
func expectEqual<T: BinaryFloatingPoint>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, accuracy: T, file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try lhs(), b = try rhs(); if !(abs(a-b) <= accuracy) { recordFailure("\(a) != \(b), tolerance \(accuracy)", file, line) } }
    catch { recordFailure(String(describing: error), file, line) }
}
func expectTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { recordFailure("Expected true", file, line) } }
    catch { recordFailure(String(describing: error), file, line) }
}
'''
runner = '\nlet checks = ParserTests()\n'
for name, throws in cases:
    call = ('try ' if throws else '') + f'checks.{name}()'
    if throws:
        runner += f'do {{ {call} }} catch {{ recordFailure("{name}: \\(error)", #filePath, #line) }}\n'
    else:
        runner += call + '\n'
runner += f'if failures != 0 {{ exit(1) }}\nprint("Passed {len(cases)} core regression cases (standalone runner, not XCTest).")\n'
build = root / '.build/standalone-tests'
build.mkdir(parents=True, exist_ok=True)
main = build / 'main.swift'
main.write_text(helpers + '\n' + source + runner)
command = ['xcrun', 'swiftc', '-module-cache-path', str(build / 'module-cache')]
command += [str(p) for p in sorted((root / 'Sources/ChemCraftCore').glob('*.swift'))]
command += [str(main), '-o', str(build / 'core-regressions')]
subprocess.run(command, check=True, cwd=root)
subprocess.run([str(build / 'core-regressions')], check=True, cwd=root)
