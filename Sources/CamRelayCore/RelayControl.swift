import Foundation

public struct NamedFixture: Codable, Equatable, Sendable {
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public enum RelayPlatform: String, Equatable, Sendable {
    case iOS = "ios"
    case android
}

public struct RelayRunOptions: Equatable, Sendable {
    public var platform: RelayPlatform = .iOS
    public var session = "default"
    public var fixtures: [NamedFixture] = []
    public var initial: String?
    public var paused = false
    public var noInteractive = false
    public var androidAVD: String?

    public init() {}
}

public enum RelayAction: String, Codable, Sendable {
    case select, replay, pause, play, next, previous, status, stop
}

public struct RelayControlRequest: Codable, Equatable, Sendable {
    public let action: RelayAction
    public var fixture: String?
    public var paused: Bool
    public var waitForFrame: Bool
    public var timeout: Double

    public init(
        action: RelayAction,
        fixture: String? = nil,
        paused: Bool = false,
        waitForFrame: Bool = false,
        timeout: Double = 10
    ) {
        self.action = action
        self.fixture = fixture
        self.paused = paused
        self.waitForFrame = waitForFrame
        self.timeout = timeout
    }

    public func validate() throws {
        guard timeout.isFinite, timeout > 0, timeout <= 300 else {
            throw RelayError("Timeout must be greater than zero and at most 300 seconds.")
        }
        if action == .select {
            guard let fixture, !fixture.isEmpty else { throw RelayError("Select requires a fixture name.") }
        } else if fixture != nil {
            throw RelayError("Only select accepts a fixture name.")
        }
        if paused && ![.select, .replay, .next, .previous].contains(action) {
            throw RelayError("--paused is supported by select, replay, next, and previous.")
        }
        if waitForFrame && [.status, .stop].contains(action) {
            throw RelayError("--wait-for-frame requires a playback command.")
        }
    }
}

public struct RelayStatus: Codable, Equatable, Sendable {
    public let session: String
    public let simulator: String
    public let simulatorID: String
    public let fixtures: [String]
    public let selected: String
    public let paused: Bool
    public let generation: UInt64
    public let positionSeconds: Double
    public let connectedReceivers: Int
    public let acknowledgedReceivers: Int
    public let width: Int
    public let height: Int
    public let framesPerSecond: Int
    public let error: String?

    public init(
        session: String, simulator: String, simulatorID: String, fixtures: [String],
        selected: String, paused: Bool, generation: UInt64, positionSeconds: Double,
        connectedReceivers: Int, acknowledgedReceivers: Int,
        width: Int, height: Int, framesPerSecond: Int, error: String?
    ) {
        self.session = session
        self.simulator = simulator
        self.simulatorID = simulatorID
        self.fixtures = fixtures
        self.selected = selected
        self.paused = paused
        self.generation = generation
        self.positionSeconds = positionSeconds
        self.connectedReceivers = connectedReceivers
        self.acknowledgedReceivers = acknowledgedReceivers
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.error = error
    }
}

public struct RelayControlResponse: Codable, Sendable {
    public let status: RelayStatus?
    public let error: String?

    public init(status: RelayStatus? = nil, error: String? = nil) {
        self.status = status
        self.error = error
    }
}

public struct RelayError: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum RelayCommand: Equatable, Sendable {
    case help
    case version
    case run(RelayRunOptions)
    case control(session: String, request: RelayControlRequest, json: Bool, waitForReady: Bool)

    public static func parse(_ arguments: [String]) throws -> RelayCommand {
        if arguments == ["--help"] || arguments == ["-h"] { return .help }
        if arguments == ["--version"] { return .version }
        guard !arguments.isEmpty else { throw RelayError("Expected a media path or a command. Use --help for usage.") }

        if let action = RelayAction(rawValue: arguments[0]) {
            return try parseControl(Array(arguments.dropFirst()), action: action, waitForReady: false)
        }
        if arguments[0] == "wait" {
            return try parseControl(Array(arguments.dropFirst()), action: .status, waitForReady: true)
        }
        return .run(try parseRun(arguments[0] == "run" ? Array(arguments.dropFirst()) : arguments))
    }

    public static func validateName(_ name: String, kind: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !name.isEmpty, name.utf8.count <= 48,
              name.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              name.first != "-" else {
            throw RelayError("\(kind) must contain 1–48 letters, digits, underscores, or hyphens and cannot start with a hyphen.")
        }
    }

    private static func parseRun(_ arguments: [String]) throws -> RelayRunOptions {
        var options = RelayRunOptions()
        var index = 0
        var positionalOnly = false
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if positionalOnly {
                options.fixtures.append(NamedFixture(name: "fixture-\(options.fixtures.count + 1)", path: argument))
                continue
            }
            switch argument {
            case "--": positionalOnly = true
            case "--platform":
                let rawPlatform = try value(arguments, index: &index, option: argument)
                guard let platform = RelayPlatform(rawValue: rawPlatform) else {
                    throw RelayError("Unknown platform: \(rawPlatform). Expected ios or android.")
                }
                options.platform = platform
            case "--session": options.session = try value(arguments, index: &index, option: argument)
            case "--initial": options.initial = try value(arguments, index: &index, option: argument)
            case "--paused": options.paused = true
            case "--no-interactive": options.noInteractive = true
            case "--avd": options.androidAVD = try value(arguments, index: &index, option: argument)
            case "--fixture":
                let specification = try value(arguments, index: &index, option: argument)
                let parts = specification.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, !parts[1].isEmpty else {
                    throw RelayError("--fixture expects name=path.")
                }
                options.fixtures.append(NamedFixture(name: String(parts[0]), path: String(parts[1])))
            default:
                guard !argument.hasPrefix("-") else { throw RelayError("Unknown option: \(argument)") }
                options.fixtures.append(NamedFixture(name: "fixture-\(options.fixtures.count + 1)", path: argument))
            }
        }
        try validateName(options.session, kind: "Session name")
        if options.platform == .iOS, options.androidAVD != nil {
            throw RelayError("--avd requires --platform android.")
        }
        if let avd = options.androidAVD {
            try validateName(avd, kind: "AVD name")
        }
        guard !options.fixtures.isEmpty else { throw RelayError("Provide at least one media path or --fixture name=path.") }
        var names: Set<String> = []
        for fixture in options.fixtures {
            try validateName(fixture.name, kind: "Fixture name")
            guard names.insert(fixture.name).inserted else { throw RelayError("Duplicate fixture name: \(fixture.name)") }
        }
        if let initial = options.initial, !names.contains(initial) {
            throw RelayError("Unknown initial fixture: \(initial)")
        }
        return options
    }

    private static func parseControl(
        _ arguments: [String], action: RelayAction, waitForReady: Bool
    ) throws -> RelayCommand {
        var session = "default"
        var request = RelayControlRequest(action: action)
        var json = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            switch argument {
            case "--session": session = try value(arguments, index: &index, option: argument)
            case "--json": json = true
            case "--paused": request.paused = true
            case "--wait-for-frame": request.waitForFrame = true
            case "--timeout":
                let raw = try value(arguments, index: &index, option: argument)
                let seconds = raw.hasSuffix("s") ? String(raw.dropLast()) : raw
                guard let timeout = Double(seconds) else { throw RelayError("Invalid timeout: \(raw)") }
                request.timeout = timeout
            default:
                guard action == .select, request.fixture == nil, !argument.hasPrefix("-") else {
                    throw RelayError("Unexpected argument: \(argument)")
                }
                request.fixture = argument
            }
        }
        try validateName(session, kind: "Session name")
        try request.validate()
        return .control(session: session, request: request, json: json, waitForReady: waitForReady)
    }

    private static func value(_ arguments: [String], index: inout Int, option: String) throws -> String {
        guard index < arguments.count, !arguments[index].hasPrefix("--") else {
            throw RelayError("\(option) requires a value.")
        }
        defer { index += 1 }
        return arguments[index]
    }
}
