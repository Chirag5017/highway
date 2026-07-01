import HighwayCore
import Foundation
import Terminal
import Arguments
import HighwayProject
import Git
import Url

extension GitAutotag {
    func nextVersion(at cwd: Absolute) throws -> String {
        return try autotag(at: cwd, dryRun: true)
    }
}

enum CustomHighway: String, HighwayType {
    case test
    case build
    case release
    case updateVersion
    case release_then_upload

    var usage: String {
        switch self {
        case .test:
            return "Execute all unit and integration tests."
        case .build:
            return "Build the highway project."
        case .release:
            return "Create and publish a new release."
        case .release_then_upload:
            return "Create and publish a release, then upload it."
        case .updateVersion:
            return "Write the next tag to CurrentVersion.swift and tag the repository."
        }
    }
}

final class App: Highway<CustomHighway> {
    override func setupHighways() {
        self[.test] ==> runTests
        self[.release].depends(on: .test, .updateVersion, .build) ==> release
        self[.build].depends(on: .test) ==> build
        self[.updateVersion] ==> updateVersionAndTag
        self[.release_then_upload].depends(on: .release) ==> releaseThenUpload
        self.onError = handleError
    }

    func updateVersionAndTag() throws -> String {
        let nextVersion = try GitAutotag(system: system).nextVersion(at: cwd)
        try update(nextVersion: nextVersion, currentDirectoryURL: cwd, fileSystem: context.fileSystem)

        try git.addAll(at: cwd)
        try git.commit(at: cwd, message: "Release \(nextVersion)")
        _ = try GitAutotag(system: system).autotag(at: cwd, dryRun: false)

        ui.message("New version: \(nextVersion)")
        return nextVersion
    }

    func handleError(_ error: Swift.Error) {
        print(error)
        exit(EXIT_FAILURE)
    }

    func runTests() throws {
        try SwiftBuildSystem().test()
    }

    func build() throws -> SwiftBuildSystem.Artifact {
        let buildOptions = SwiftOptions(
            subject: .auto,
            projectDirectory: cwd,
            configuration: .release,
            verbose: true,
            additionalArguments: []
        )
        let buildSystem = SwiftBuildSystem(context: context)
        let plan = try buildSystem.executionPlan(with: buildOptions)
        return try buildSystem.execute(plan: plan)
    }

    func release() throws {
        ui.message("Releasing...")
    }

    func releaseThenUpload() throws {
        try git.pushToMaster(at: cwd)
        try git.pushTagsToMaster(at: cwd)
    }
}

App(CustomHighway.self).go()
