import Testing
@testable import CleanerCore

struct XcodeJsonTests {
    private func fixture(_ name: String) throws -> String {
        try XcodeFixtures.text(name)
    }

    private func single(_ snapshot: XcodeSnapshot, _ kind: XcodeResourceKind) throws -> XcodeCandidate {
        let matching = snapshot.candidates.filter { $0.kind == kind }
        #expect(matching.count == 1)
        return try #require(matching.first)
    }

    @Test func malformedDevicesProducesWarningAndBlocksRuntimes() throws {
        let snapshot = XcodeJson.parseInventory(try fixture("malformed-devices.json"), try fixture("runtime-list.json"), runtimeDeleteSupported: true)

        #expect(snapshot.warnings.contains { $0.resourceGroup == .device && $0.kind == .completenessFailure && !$0.message.isEmpty })
        let runtime = try single(snapshot, .runtime)
        #expect(!runtime.canSelect)
        #expect(XcodeText.containsIgnoringCase(try #require(runtime.blockReason), "simulatori"))
    }

    @Test func sameVersionDifferentBuildDoesNotGuess() throws {
        let simctl = """
            {"devices":{},"runtimes":[
              {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18.0","version":"18.0","buildversion":"22A4000","platform":"iOS"}]}
            """
        let images = """
            {
              "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE":{"identifier":"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","build":"22A4000","deletable":true},
              "BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF":{"identifier":"BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","build":"22A5000","deletable":true}
            }
            """

        let snapshot = XcodeJson.parseInventory(simctl, images, runtimeDeleteSupported: true)

        #expect(snapshot.warnings.contains { $0.resourceGroup == .runtime })
        let runtimes = snapshot.candidates.filter { $0.kind == .runtime }
        #expect(runtimes.count == 2)
        #expect(runtimes.allSatisfy { !$0.canSelect && $0.runtimeIdentifier == nil })
    }

    @Test func missingRemovalUuidBlocksRuntime() throws {
        let snapshot = XcodeJson.parseInventory(try fixture("simctl-list.json"), try fixture("runtime-list-missing-uuid.json"), runtimeDeleteSupported: true)

        let runtime = try single(snapshot, .runtime)
        #expect(!runtime.canSelect)
        #expect(XcodeText.containsIgnoringCase(try #require(runtime.blockReason), "UUID"))
    }

    @Test func malformedDeviceSourceStillKeepsRuntimeVisible() throws {
        let snapshot = XcodeJson.parseInventory("{", try fixture("runtime-list.json"), runtimeDeleteSupported: true)

        #expect(snapshot.candidates.contains { $0.kind == .runtime })
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device })
    }

    @Test func emptyJsonInventoryIsSuccessful() {
        let snapshot = XcodeJson.parseInventory(#"{"runtimes":[],"devices":{}}"#, "{}", runtimeDeleteSupported: true)

        #expect(snapshot.candidates.isEmpty)
        #expect(snapshot.warnings.isEmpty)
    }

    @Test func missingRuntimeMetadataKeepsValidDeviceEntry() throws {
        let simctl = """
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Shutdown"}]}}
            """

        let snapshot = XcodeJson.parseInventory(simctl, try fixture("runtime-list.json"), runtimeDeleteSupported: true)

        let device = try single(snapshot, .device)
        #expect(device.cliId == "11111111-1111-4111-8111-111111111111")
        #expect(device.canSelect)
        #expect(snapshot.warnings.contains { $0.resourceGroup == .runtime })
        #expect(try !single(snapshot, .runtime).canSelect)
    }

    @Test func malformedDeviceSiblingPreservesKnownDeviceButBlocksDeletion() throws {
        let simctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Shutdown"},
              {"udid":"invalid","name":"Broken device","state":"Shutdown"}]}}
            """

        let snapshot = XcodeJson.parseInventory(simctl, "{}", runtimeDeleteSupported: true)

        let device = try single(snapshot, .device)
        #expect(device.cliId == "11111111-1111-4111-8111-111111111111")
        #expect(!device.canSelect)
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device })
    }

    @Test func unknownDeviceStateBlocksDeviceAndDependentRuntime() throws {
        let simctl = """
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"MysteryState"}]},
             "runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18.0","version":"18.0","buildversion":"22A3351","platform":"iOS"}]}
            """

        let snapshot = XcodeJson.parseInventory(simctl, try fixture("runtime-list.json"), runtimeDeleteSupported: true)

        #expect(try !single(snapshot, .device).canSelect)
        #expect(try !single(snapshot, .runtime).canSelect)
    }

    @Test func unavailableDeviceIsKnownNonrunningAndDoesNotBlockRuntime() throws {
        let simctl = """
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Unavailable"}]},
             "runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18.0","version":"18.0","buildversion":"22A3351","platform":"iOS"}]}
            """

        let snapshot = XcodeJson.parseInventory(simctl, try fixture("runtime-list.json"), runtimeDeleteSupported: true)

        let classified = try XcodeClassifier.classify(snapshot, xcodeRunning: false)
        let device = try single(classified, .device)
        let runtime = try single(classified, .runtime)
        #expect(!snapshot.warnings.contains { $0.resourceGroup == .device && $0.kind == .completenessFailure })
        #expect(runtime.canSelect)
        #expect(runtime.dependentDeviceKeys.contains(device.key))
    }

    @Test func unavailableDeviceRetainsIndependentIdentityBlock() throws {
        let simctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Unavailable"},
              {"udid":"11111111-1111-4111-8111-111111111111","name":"Different device","state":"Unavailable"}]}}
            """

        let classified = try XcodeClassifier.classify(XcodeJson.parseInventory(simctl, "{}", runtimeDeleteSupported: true), xcodeRunning: false)

        let device = try single(classified, .device)
        #expect(!device.canSelect)
        #expect(XcodeText.containsIgnoringCase(try #require(device.blockReason), "conflitto"))
    }

    @Test func nonObjectJsonRootReturnsWarningsWithoutThrowing() {
        let snapshot = XcodeJson.parseInventory("[]", "{}", runtimeDeleteSupported: true)

        #expect(snapshot.candidates.isEmpty)
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device })
        #expect(snapshot.warnings.contains { $0.resourceGroup == .runtime })
    }

    @Test func nonnumericDeviceSizePreservesSiblingWithUnknownSizeAndWarning() {
        let simctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Shutdown","dataPathSize":100},
              {"udid":"22222222-2222-4222-8222-222222222222","name":"iPhone 16 Pro","state":"Shutdown","dataPathSize":[]}]}}
            """

        let snapshot = XcodeJson.parseInventory(simctl, "{}", runtimeDeleteSupported: true)

        let devices = snapshot.candidates.filter { $0.kind == .device }
        #expect(devices.count == 2)
        #expect(devices.first?.sizeBytes == 100)
        #expect(devices.last?.sizeBytes == nil)
        #expect(devices.allSatisfy { $0.canSelect })
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device && $0.kind == .advisory })
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device })
    }

    @Test func deviceSizeAdvisoryDoesNotMaskIncompleteDeviceInventory() {
        let simctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"33333333-3333-4333-8333-333333333333","name":"iPhone 16","state":"Shutdown","dataPathSize":[]},
              {"name":"missing UUID","state":"Shutdown"}]}}
            """

        let snapshot = XcodeJson.parseInventory(simctl, "{}", runtimeDeleteSupported: true)

        #expect(snapshot.warnings.contains { $0.resourceGroup == .device && $0.kind == .advisory })
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device && $0.kind == .completenessFailure })
    }

    @Test func runtimeCandidateKeepsBackingPathAndLeavesAllocatedSizeUnknownUntilProbed() throws {
        let path = "/System/Library/AssetsV2/runtime.asset/AssetData"
        let simctl = #"{"runtimes":[],"devices":{}}"#
        let images = """
            {"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE":{"identifier":"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","build":"22A4000","deletable":true,"path":"/System/Library/AssetsV2/runtime.asset/AssetData","mountPath":"/private/var/run/mounted-runtime","sizeBytes":999999}}
            """

        let snapshot = XcodeJson.parseInventory(simctl, images, runtimeDeleteSupported: true)

        let runtime = try single(snapshot, .runtime)
        #expect(runtime.path == path)
        #expect(runtime.sizeBytes == nil)
        #expect(runtime.key == "runtime:aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        #expect(runtime.cliId == "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
    }

    @Test func conflictingRepeatedDeviceUuidIsDeduplicatedAndBlocked() throws {
        let uuid = "abcdefab-cdef-4abc-8def-abcdefabcdef"
        let simctl = """
            {"devices":{
              "com.apple.CoreSimulator.SimRuntime.iOS-18-0":[{"udid":"abcdefab-cdef-4abc-8def-abcdefabcdef","name":"iPhone 16","state":"Shutdown","dataPathSize":100}],
              "com.apple.CoreSimulator.SimRuntime.watchOS-11-0":[{"udid":"ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF","name":"iPhone 16","state":"Shutdown","dataPathSize":200}]},
             "runtimes":[
               {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18.0","version":"18.0","buildversion":"22A000","platform":"iOS"},
               {"identifier":"com.apple.CoreSimulator.SimRuntime.watchOS-11-0","name":"watchOS 11.0","version":"11.0","buildversion":"22B000","platform":"watchOS"}]}
            """
        let runtimeJson = """
            {
              "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE":{"identifier":"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","build":"22A000","deletable":true},
              "BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF":{"identifier":"BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.watchOS-11-0","version":"11.0","build":"22B000","deletable":true}
            }
            """

        let snapshot = XcodeJson.parseInventory(simctl, runtimeJson, runtimeDeleteSupported: true)

        let device = try single(snapshot, .device)
        #expect(device.key == uuid)
        #expect(device.cliId == uuid)
        #expect(!device.canSelect)
        #expect(device.sizeBytes == nil)
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device && XcodeText.containsIgnoringCase($0.message, "UUID") })
        let runtimes = snapshot.candidates.filter { $0.kind == .runtime }
        #expect(runtimes.count == 2)
        #expect(runtimes.allSatisfy { XcodeText.containsIgnoringCase($0.blockReason ?? "", "UUID") })
        #expect(runtimes.flatMap(\.dependentDeviceKeys).allSatisfy { $0 == uuid })
    }
}
