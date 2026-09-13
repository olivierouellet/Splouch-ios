import Testing
@testable import SplouchCore

@Suite struct DeltaFormatTests {
    @Test func mirrorsTheServerFormatter() {
        #expect(DeltaFormat.text(-0.46) == "-0.46")
        #expect(DeltaFormat.text(0.46) == "+0.46")
        #expect(DeltaFormat.text(0) == "+0.00")
        #expect(DeltaFormat.text(12.05) == "+12.05")
        #expect(DeltaFormat.text(75.3) == "+1:15.30")
        #expect(DeltaFormat.text(-61.0) == "-1:01.00")
        #expect(DeltaFormat.text(nil) == "")
        #expect(DeltaFormat.text(.nan) == "")
    }
}
