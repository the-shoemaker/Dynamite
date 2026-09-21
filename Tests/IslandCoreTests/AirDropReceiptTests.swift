import Testing
@testable import IslandCore

struct AirDropReceiptTests {
    private let uuid = "B4E39AE1-1827-46D8-994A-F3558A5C58A9"
    @Test func matchesOriginalNameAfterDownloadsCollision() {
        #expect(AirDropReceipt.notificationNames(for: "SamplePhoto 4.HEIC") == ["SamplePhoto 4.HEIC", "SamplePhoto.HEIC"])
        #expect(AirDropReceipt.notificationNames(for: "SamplePhoto.HEIC") == ["SamplePhoto.HEIC"])
        #expect(AirDropReceipt.notificationNames(for: "Report final.pdf") == ["Report final.pdf"])
        #expect(AirDropReceipt.notificationNames(for: "Report 1.pdf") == ["Report 1.pdf"])
    }
    @Test func acceptsFreshSharingReceiptOnly() {
        #expect(AirDropReceipt(quarantine: "0081;64;sharingd;\(uuid)", since: 99.5, now: 101)?.receivedAt == 100)
        #expect(AirDropReceipt(quarantine: "0081;64;Safari;\(uuid)", since: 99, now: 101) == nil)
        #expect(AirDropReceipt(quarantine: "0081;64;sharingd;\(uuid)", since: 102, now: 103) == nil)
        #expect(AirDropReceipt(quarantine: "0081;ffff;sharingd;\(uuid)", since: 99, now: 101) == nil)
        #expect(AirDropReceipt(quarantine: "0081;64;sharingd;bad", since: 99, now: 101) == nil)
    }
}
