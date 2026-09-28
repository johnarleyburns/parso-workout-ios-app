import Foundation

/// Minimal, standards-compatible FIT activity codec.
///
/// FIT is an interchange format for recorded activities, not a general
/// application backup. This codec preserves cardio sessions, duration,
/// distance, calories, heart-rate summaries, heart-rate samples, and route
/// samples. Strength sets, assessments, preferences, and Coach state remain
/// JSON-only because FIT has no portable representation for them.
public enum FITExport {
    public enum Error: Swift.Error, Equatable, LocalizedError {
        case invalidHeader
        case invalidHeaderCRC
        case invalidDataCRC
        case truncated
        case unsupportedDefinition
        case noActivities
        case dateOutOfRange

        public var errorDescription: String? {
            switch self {
            case .invalidHeader: "That file is not a valid FIT activity file."
            case .invalidHeaderCRC: "The FIT file header is corrupted."
            case .invalidDataCRC: "The FIT file data is corrupted."
            case .truncated: "The FIT file ended before all of its data was available."
            case .unsupportedDefinition: "This FIT file uses an unsupported message definition."
            case .noActivities: "The FIT file contains no recorded activities."
            case .dateOutOfRange: "A workout date cannot be represented by FIT."
            }
        }
    }

    private static let fitEpoch = Date(timeIntervalSince1970: 631_065_600)
    private static let fitSignature = Array(".FIT".utf8)

    public static func isFIT(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        return Array(data[8..<12]) == fitSignature
    }

    public static func encode(_ cardio: [ExportCardio]) throws -> Data {
        var body: [UInt8] = []
        let definitions = Definitions()
        var localDefinitions: Set<Int> = []

        func emit(_ message: Message, local: Int) {
            let definition = definitions.definition(for: message.global)
            if !localDefinitions.contains(local) {
                appendDefinition(definition, local: local, to: &body)
                localDefinitions.insert(local)
            }
            body.append(UInt8(local))
            for field in definition.fields {
                body.append(contentsOf: message.values[field.number] ?? invalidBytes(for: field))
            }
        }

        let firstDate = cardio.map(\.start).min() ?? Date()
        emit(fileIDMessage(createdAt: firstDate), local: 0)

        for workout in cardio {
            let start = workout.start
            let end = workout.end ?? start
            let endDate = max(start, end)
            let startTimestamp = try timestamp(start)
            let endTimestamp = try timestamp(endDate)
            let elapsed = max(0, endDate.timeIntervalSince(start))
            let records = recordTimes(for: workout, duration: elapsed)

            emit(sessionMessage(for: workout, startTimestamp: startTimestamp,
                                endTimestamp: endTimestamp, elapsed: elapsed), local: 1)
            for time in records {
                emit(recordMessage(for: workout, time: time, duration: elapsed,
                                   startTimestamp: startTimestamp), local: 2)
            }
            emit(lapMessage(for: workout, endTimestamp: endTimestamp, elapsed: elapsed), local: 3)
            emit(activityMessage(endTimestamp: endTimestamp, elapsed: elapsed), local: 4)
        }

        var output: [UInt8] = []
        var headerWithoutCRC: [UInt8] = [
            14,             // header size
            0x20,           // FIT protocol 2.0
            0x10, 0x08      // profile version 2.16
        ]
        headerWithoutCRC.append(contentsOf: u32(UInt32(body.count)))
        headerWithoutCRC.append(contentsOf: fitSignature)
        output.append(contentsOf: headerWithoutCRC)
        output.append(contentsOf: u16(crc16(headerWithoutCRC)))
        output.append(contentsOf: body)
        output.append(contentsOf: u16(crc16(body)))
        return Data(output)
    }

    public static func decode(_ data: Data) throws -> [ExportCardio] {
        let bytes = Array(data)
        guard bytes.count >= 14, isFIT(data) else { throw Error.invalidHeader }
        let headerSize = Int(bytes[0])
        guard headerSize >= 12, headerSize <= bytes.count else { throw Error.invalidHeader }
        let bodySize = Int(readUInt32(bytes, at: 4, littleEndian: true))
        let bodyStart = headerSize
        let bodyEnd = bodyStart + bodySize
        guard bodyEnd + 2 <= bytes.count else { throw Error.truncated }
        if headerSize >= 14 {
            let expected = readUInt16(bytes, at: headerSize - 2, littleEndian: true)
            let actual = crc16(Array(bytes[0..<(headerSize - 2)]))
            guard expected == actual else { throw Error.invalidHeaderCRC }
        }
        let expectedDataCRC = readUInt16(bytes, at: bodyEnd, littleEndian: true)
        let actualDataCRC = crc16(Array(bytes[bodyStart..<bodyEnd]))
        guard expectedDataCRC == actualDataCRC else { throw Error.invalidDataCRC }

        var definitions: [Int: Definition] = [:]
        var sessions: [SessionDraft] = []
        var records: [RecordDraft] = []
        var cursor = bodyStart
        var lastTimestamp: UInt32?

        while cursor < bodyEnd {
            let header = bytes[cursor]
            cursor += 1
            if header & 0x40 != 0 {
                let local = Int(header & 0x0F)
                guard cursor + 5 <= bodyEnd else { throw Error.truncated }
                let architecture = bytes[cursor]
                cursor += 1
                let global = readUInt16(bytes, at: cursor, littleEndian: architecture == 0)
                cursor += 2
                let fieldCount = Int(bytes[cursor])
                cursor += 1
                guard cursor + fieldCount * 3 <= bodyEnd else { throw Error.truncated }
                var fields: [Field] = []
                for _ in 0..<fieldCount {
                    fields.append(Field(number: bytes[cursor], size: Int(bytes[cursor + 1]),
                                        baseType: bytes[cursor + 2], architecture: architecture))
                    cursor += 3
                }
                definitions[local] = Definition(global: global, fields: fields)
                continue
            }

            let compressed = header & 0x80 != 0
            let local = compressed ? Int((header >> 5) & 0x03) : Int(header & 0x0F)
            guard let definition = definitions[local] else { throw Error.unsupportedDefinition }
            var values: [UInt8: Scalar] = [:]
            var compressedTimestamp: UInt32?
            if compressed {
                guard let lastTimestamp else { throw Error.unsupportedDefinition }
                let offset = UInt32(header & 0x1F)
                let base = lastTimestamp & ~UInt32(0x1F)
                var candidate = base | offset
                if candidate <= lastTimestamp { candidate += 0x20 }
                compressedTimestamp = candidate
            }
            for field in definition.fields {
                if compressed && field.number == 253 {
                    continue
                }
                guard cursor + field.size <= bodyEnd else { throw Error.truncated }
                let fieldBytes = Array(bytes[cursor..<(cursor + field.size)])
                cursor += field.size
                if let scalar = decodeScalar(fieldBytes, baseType: field.baseType,
                                             architecture: field.architecture) {
                    values[field.number] = scalar
                }
            }
            if let compressedTimestamp {
                values[253] = .unsigned(UInt64(compressedTimestamp))
            }
            if let timestamp = values[253]?.unsignedValue {
                lastTimestamp = UInt32(clamping: timestamp)
            }
            switch definition.global {
            case 18:
                sessions.append(SessionDraft(values: values))
            case 20:
                records.append(RecordDraft(values: values))
            default:
                break
            }
        }

        if sessions.isEmpty, !records.isEmpty {
            let timestamps = records.compactMap { $0.timestamp }
            guard let first = timestamps.min() else { throw Error.noActivities }
            let last = timestamps.max() ?? first
            sessions = [SessionDraft(start: first, end: last)]
        }
        guard !sessions.isEmpty else { throw Error.noActivities }

        let decoded = sessions.compactMap { session -> ExportCardio? in
            guard let startTimestamp = session.startTimestamp else { return nil }
            let start = date(for: startTimestamp)
            let fallbackEnd = start.addingTimeInterval(session.elapsedSeconds ?? 0)
            let end = session.endTimestamp.map(date(for:)) ?? fallbackEnd
            let endTimestamp = session.endTimestamp ?? (try? timestamp(end))
            let matchingRecords = records.filter { record in
                guard let timestamp = record.timestamp else { return false }
                guard let endTimestamp else { return timestamp >= startTimestamp }
                return timestamp >= startTimestamp && timestamp <= endTimestamp + 1
            }
            let hrSamples = matchingRecords.compactMap { record -> ExportHRSample? in
                guard let bpm = record.heartRate, let timestamp = record.timestamp else { return nil }
                return ExportHRSample(t: max(0, Double(timestamp - startTimestamp)), bpm: bpm)
            }
            let routeSamples = matchingRecords.compactMap { record -> ExportRouteSample? in
                guard let lat = record.latitude, let lon = record.longitude,
                      let timestamp = record.timestamp else { return nil }
                return ExportRouteSample(t: max(0, Double(timestamp - startTimestamp)),
                                         lat: lat, lon: lon, elevation: record.elevation ?? 0)
            }
            let averageHR = session.averageHeartRate ?? average(hrSamples.map(\.bpm))
            let maximumHR = session.maximumHeartRate ?? hrSamples.map(\.bpm).max()
            return ExportCardio(id: UUID(), type: cardioType(for: session.sport), start: start,
                                end: end, distanceMeters: session.distanceMeters,
                                activeEnergyKcal: session.calories,
                                avgHeartRate: averageHR, source: CardioSource.watch.rawValue,
                                maxHeartRate: maximumHR, isLogged: true,
                                importedWorkoutKindRaw: importedKind(for: session.sport),
                                hrSamples: hrSamples.isEmpty ? nil : hrSamples,
                                routeSamples: routeSamples.isEmpty ? nil : routeSamples)
        }
        guard !decoded.isEmpty else { throw Error.noActivities }
        return decoded
    }

    // MARK: FIT message construction

    private struct Field {
        let number: UInt8
        let size: Int
        let baseType: UInt8
        let architecture: UInt8
    }

    private struct Definition {
        let global: UInt16
        let fields: [Field]
    }

    private struct Message {
        let global: UInt16
        let values: [UInt8: [UInt8]]
    }

    private struct Definitions {
        private let all: [UInt16: Definition] = [
            0: Definition(global: 0, fields: [
                Field(number: 0, size: 1, baseType: 0x00, architecture: 0),
                Field(number: 1, size: 2, baseType: 0x84, architecture: 0),
                Field(number: 2, size: 2, baseType: 0x84, architecture: 0),
                Field(number: 3, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 4, size: 4, baseType: 0x86, architecture: 0)
            ]),
            18: Definition(global: 18, fields: [
                Field(number: 253, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 0, size: 1, baseType: 0x00, architecture: 0),
                Field(number: 1, size: 1, baseType: 0x00, architecture: 0),
                Field(number: 2, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 3, size: 4, baseType: 0x85, architecture: 0),
                Field(number: 4, size: 4, baseType: 0x85, architecture: 0),
                Field(number: 5, size: 1, baseType: 0x00, architecture: 0),
                Field(number: 6, size: 1, baseType: 0x00, architecture: 0),
                Field(number: 7, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 8, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 9, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 11, size: 2, baseType: 0x84, architecture: 0),
                Field(number: 16, size: 1, baseType: 0x02, architecture: 0),
                Field(number: 17, size: 1, baseType: 0x02, architecture: 0),
                Field(number: 25, size: 2, baseType: 0x84, architecture: 0),
                Field(number: 26, size: 2, baseType: 0x84, architecture: 0)
            ]),
            19: Definition(global: 19, fields: [
                Field(number: 253, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 0, size: 1, baseType: 0x00, architecture: 0),
                Field(number: 1, size: 1, baseType: 0x00, architecture: 0),
                Field(number: 2, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 7, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 8, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 9, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 11, size: 2, baseType: 0x84, architecture: 0),
                Field(number: 15, size: 1, baseType: 0x02, architecture: 0),
                Field(number: 16, size: 1, baseType: 0x02, architecture: 0)
            ]),
            20: Definition(global: 20, fields: [
                Field(number: 253, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 0, size: 4, baseType: 0x85, architecture: 0),
                Field(number: 1, size: 4, baseType: 0x85, architecture: 0),
                Field(number: 2, size: 2, baseType: 0x84, architecture: 0),
                Field(number: 3, size: 1, baseType: 0x02, architecture: 0),
                Field(number: 5, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 6, size: 2, baseType: 0x84, architecture: 0)
            ]),
            34: Definition(global: 34, fields: [
                Field(number: 253, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 0, size: 4, baseType: 0x86, architecture: 0),
                Field(number: 1, size: 2, baseType: 0x84, architecture: 0),
                Field(number: 2, size: 1, baseType: 0x00, architecture: 0),
                Field(number: 3, size: 1, baseType: 0x00, architecture: 0),
                Field(number: 4, size: 1, baseType: 0x00, architecture: 0)
            ])
        ]

        func definition(for global: UInt16) -> Definition { all[global]! }
    }

    private static func appendDefinition(_ definition: Definition, local: Int, to body: inout [UInt8]) {
        body.append(0x40 | UInt8(local))
        body.append(0) // little-endian architecture
        body.append(contentsOf: u16(definition.global))
        body.append(UInt8(definition.fields.count))
        for field in definition.fields {
            body.append(field.number)
            body.append(UInt8(field.size))
            body.append(field.baseType)
        }
    }

    private static func fileIDMessage(createdAt: Date) -> Message {
        Message(global: 0, values: [0: [4], 1: u16(1), 2: u16(0), 3: u32(0),
                                     4: (try? timestamp(createdAt)).map(u32) ?? u32(0)])
    }

    private static func sessionMessage(for workout: ExportCardio, startTimestamp: UInt32,
                                       endTimestamp: UInt32, elapsed: TimeInterval) -> Message {
        let route = workout.routeSamples?.min { $0.t < $1.t }
        var values: [UInt8: [UInt8]] = [
            253: u32(endTimestamp), 0: [8], 1: [0], 2: u32(startTimestamp),
            5: [sport(for: workout.type)], 6: [0],
            7: u32(milliseconds(elapsed)), 8: u32(milliseconds(elapsed)),
            9: u32(scaledUInt32(workout.distanceMeters, scale: 100)),
            11: u16(scaledUInt16(workout.activeEnergyKcal, scale: 1)),
            16: u8(workout.avgHeartRate), 17: u8(workout.maxHeartRate),
            25: u16(0), 26: u16(1)
        ]
        if let route {
            values[3] = sint32(semicircles(route.lat))
            values[4] = sint32(semicircles(route.lon))
        }
        return Message(global: 18, values: values)
    }

    private static func recordMessage(for workout: ExportCardio, time: TimeInterval,
                                      duration: TimeInterval, startTimestamp: UInt32) -> Message {
        let hr = workout.hrSamples?.first { abs($0.t - time) < 0.01 }
        let route = workout.routeSamples?.first { abs($0.t - time) < 0.01 }
        var values: [UInt8: [UInt8]] = [253: u32(startTimestamp + UInt32(max(0, time.rounded())))]
        if let route {
            values[0] = sint32(semicircles(route.lat))
            values[1] = sint32(semicircles(route.lon))
            values[2] = u16(scaledUInt16(route.elevation + 500, scale: 5))
        }
        if let hr { values[3] = u8(hr.bpm) }
        if let distance = workout.distanceMeters, duration > 0 {
            values[5] = u32(scaledUInt32(distance * min(1, max(0, time / duration)), scale: 100))
        }
        if let distance = workout.distanceMeters, duration > 0 {
            values[6] = u16(scaledUInt16(distance / duration, scale: 1000))
        }
        return Message(global: 20, values: values)
    }

    private static func lapMessage(for workout: ExportCardio, endTimestamp: UInt32,
                                   elapsed: TimeInterval) -> Message {
        Message(global: 19, values: [253: u32(endTimestamp), 0: [8], 1: [0],
                                      2: u32(endTimestamp - UInt32(max(0, elapsed.rounded()))),
                                      7: u32(milliseconds(elapsed)), 8: u32(milliseconds(elapsed)),
                                      9: u32(scaledUInt32(workout.distanceMeters, scale: 100)),
                                      11: u16(scaledUInt16(workout.activeEnergyKcal, scale: 1)),
                                      15: u8(workout.avgHeartRate), 16: u8(workout.maxHeartRate)])
    }

    private static func activityMessage(endTimestamp: UInt32, elapsed: TimeInterval) -> Message {
        Message(global: 34, values: [253: u32(endTimestamp), 0: u32(milliseconds(elapsed)),
                                      1: u16(1), 2: [0], 3: [26], 4: [0]])
    }

    private static func recordTimes(for workout: ExportCardio, duration: TimeInterval) -> [TimeInterval] {
        var times = Set<Double>()
        workout.hrSamples?.forEach { times.insert(max(0, min(duration, $0.t))) }
        workout.routeSamples?.forEach { times.insert(max(0, min(duration, $0.t))) }
        if times.isEmpty { times.insert(0) }
        return times.sorted()
    }

    // MARK: Decoder support

    private struct SessionDraft {
        let values: [UInt8: Scalar]
        init(values: [UInt8: Scalar]) { self.values = values }
        init(start: UInt32, end: UInt32) {
            values = [2: .unsigned(UInt64(start)), 253: .unsigned(UInt64(end)),
                      7: .unsigned(UInt64(end - start))]
        }
        var startTimestamp: UInt32? { values[2]?.unsignedValue }
        var endTimestamp: UInt32? { values[253]?.unsignedValue }
        var elapsedSeconds: TimeInterval? { values[7]?.doubleValue.map { $0 / 1000 } }
        var distanceMeters: Double? { values[9]?.doubleValue.map { $0 / 100 } }
        var calories: Double? { values[11]?.doubleValue }
        var averageHeartRate: Double? { values[16]?.doubleValue }
        var maximumHeartRate: Double? { values[17]?.doubleValue }
        var sport: UInt8? { values[5]?.unsignedValue.map(UInt8.init) }
    }

    private struct RecordDraft {
        let values: [UInt8: Scalar]
        var timestamp: UInt32? { values[253]?.unsignedValue }
        var latitude: Double? { values[0]?.doubleValue.map { $0 * 180 / 2_147_483_648 } }
        var longitude: Double? { values[1]?.doubleValue.map { $0 * 180 / 2_147_483_648 } }
        var elevation: Double? { values[2]?.doubleValue.map { $0 / 5 - 500 } }
        var heartRate: Double? { values[3]?.doubleValue }
    }

    private enum Scalar {
        case signed(Int64)
        case unsigned(UInt64)
        case floating(Double)
        case string(String)

        var unsignedValue: UInt32? {
            switch self {
            case .signed(let value): value >= 0 ? UInt32(exactly: value) : nil
            case .unsigned(let value): UInt32(exactly: value)
            case .floating(let value): UInt32(exactly: value)
            case .string: nil
            }
        }
        var doubleValue: Double? {
            switch self {
            case .signed(let value): Double(value)
            case .unsigned(let value): Double(value)
            case .floating(let value): value
            case .string: nil
            }
        }
    }

    private static func decodeScalar(_ bytes: [UInt8], baseType: UInt8,
                                     architecture: UInt8) -> Scalar? {
        let kind = baseType & 0x1F
        let littleEndian = baseType & 0x80 != 0 ? architecture == 0 : true
        switch kind {
        case 0, 2, 10, 13:
            guard let byte = bytes.first, byte != 0xFF,
                  !(kind == 10 && byte == 0) else { return nil }
            return .unsigned(UInt64(byte))
        case 1:
            guard let byte = bytes.first, byte != 0x7F else { return nil }
            return .signed(Int64(Int8(bitPattern: byte)))
        case 3:
            let value = readUInt16(bytes, at: 0, littleEndian: littleEndian)
            guard value != 0x7FFF else { return nil }
            return .signed(Int64(Int16(bitPattern: value)))
        case 4, 11:
            let value = readUInt16(bytes, at: 0, littleEndian: littleEndian)
            guard value != 0xFFFF, !(kind == 11 && value == 0) else { return nil }
            return .unsigned(UInt64(value))
        case 5:
            let value = readUInt32(bytes, at: 0, littleEndian: littleEndian)
            return value == 0x7FFF_FFFF ? nil : .signed(Int64(Int32(bitPattern: value)))
        case 6, 12:
            let value = readUInt32(bytes, at: 0, littleEndian: littleEndian)
            guard value != 0xFFFF_FFFF, !(kind == 12 && value == 0) else { return nil }
            return .unsigned(UInt64(value))
        case 7:
            return String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8).map(Scalar.string)
        case 8:
            return bytes.count >= 4 ? .floating(Double(Float(bitPattern: readUInt32(bytes, at: 0, littleEndian: littleEndian)))) : nil
        case 9:
            guard bytes.count >= 8 else { return nil }
            let bits = bytes.enumerated().reduce(into: UInt64(0)) { result, element in
                let shift = littleEndian ? element.offset * 8 : (7 - element.offset) * 8
                result |= UInt64(element.element) << UInt64(shift)
            }
            return .floating(Double(bitPattern: bits))
        default:
            return nil
        }
    }

    private static func cardioType(for sport: UInt8?) -> String {
        switch sport {
        case 1: CardioType.run.rawValue
        case 2: CardioType.cycle.rawValue
        case 5: CardioType.swim.rawValue
        case 6: CardioType.walk.rawValue
        case 12: CardioType.rowing.rawValue
        default: CardioType.other.rawValue
        }
    }

    private static func importedKind(for sport: UInt8?) -> String? {
        switch sport {
        case 1: ImportedWorkoutKind.running.rawValue
        case 2: ImportedWorkoutKind.cycling.rawValue
        case 5: ImportedWorkoutKind.swimming.rawValue
        case 6: ImportedWorkoutKind.walking.rawValue
        case 12: ImportedWorkoutKind.rowing.rawValue
        default: ImportedWorkoutKind.other.rawValue
        }
    }

    private static func sport(for raw: String) -> UInt8 {
        switch CardioType(rawValue: raw) {
        case .run: 1
        case .cycle: 2
        case .swim: 5
        case .walk: 6
        case .rowing: 12
        default: 0
        }
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func date(for timestamp: UInt32) -> Date {
        fitEpoch.addingTimeInterval(TimeInterval(timestamp))
    }

    private static func timestamp(_ date: Date) throws -> UInt32 {
        let seconds = date.timeIntervalSince(fitEpoch)
        guard seconds >= 0, seconds <= Double(UInt32.max) else { throw Error.dateOutOfRange }
        return UInt32(seconds.rounded())
    }

    private static func milliseconds(_ seconds: TimeInterval) -> UInt32 {
        UInt32(clamping: Int64((max(0, seconds) * 1000).rounded()))
    }

    private static func semicircles(_ degrees: Double) -> Int32 {
        Int32(clamping: Int64((degrees * 2_147_483_648 / 180).rounded()))
    }

    private static func scaledUInt32(_ value: Double?, scale: Double) -> UInt32 {
        guard let value else { return .max }
        return UInt32(clamping: Int64(max(0, (value * scale).rounded())))
    }

    private static func scaledUInt16(_ value: Double?, scale: Double) -> UInt16 {
        guard let value else { return .max }
        return UInt16(clamping: Int64(max(0, (value * scale).rounded())))
    }

    private static func u8(_ value: Double?) -> [UInt8] {
        [value.map { UInt8(clamping: Int($0.rounded())) } ?? 0xFF]
    }

    private static func u16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    private static func u32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]
    }

    private static func sint32(_ value: Int32) -> [UInt8] { u32(UInt32(bitPattern: value)) }

    private static func invalidBytes(for field: Field) -> [UInt8] {
        switch field.baseType & 0x1F {
        case 5: return sint32(0x7FFF_FFFF)
        default: return Array(repeating: 0xFF, count: field.size)
        }
    }

    private static func readUInt16(_ bytes: [UInt8], at index: Int, littleEndian: Bool) -> UInt16 {
        guard index + 1 < bytes.count else { return 0 }
        if littleEndian { return UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8 }
        return UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
    }

    private static func readUInt32(_ bytes: [UInt8], at index: Int, littleEndian: Bool) -> UInt32 {
        guard index + 3 < bytes.count else { return 0 }
        if littleEndian {
            return UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8 |
                UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
        }
        return UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16 |
            UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3])
    }

    private static func crc16(_ bytes: [UInt8]) -> UInt16 {
        let table: [UInt16] = [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
                               0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400]
        var crc: UInt16 = 0
        for byte in bytes {
            crc = (crc >> 4) ^ table[Int(crc & 0x0F)]
            crc = (crc >> 4) ^ table[Int(crc & 0x0F)]
            crc ^= UInt16(byte)
        }
        return crc
    }
}
