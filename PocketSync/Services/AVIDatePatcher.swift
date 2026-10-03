//
//  AVIDatePatcher.swift
//  PocketSync
//
//  Created by Marco Ortiz Torres on 6/26/26.
//

import Foundation

nonisolated enum AVIDatePatcher {
    private static let jpegSOI: [UInt8] = [0xFF, 0xD8]
    private static let app1Marker: [UInt8] = [0xFF, 0xE1]
    private static let templateWidth = 480
    private static let templateHeight = 240
    private static let defaultClockTime = "12:00:00"

    private static let templateApp1Base64 = """
    /+EB+EV4aWYAAE1NACoAAAAIAAkBDwACAAAACQAAAHoBEAACAAAADQAAAIQBGgAFAAAAAQAAAJIBGwAFAAAAAQAAAJoBKAADAAAAAQACAAABMQACAAAABgAAAKIBMgACAAAAFAAAAKgCEwADAAAAAQACAACHaQAEAAAAAQAAALwAAAAATmludGVuZG8AAE5pbnRlbmRvIDNEUwAAAAAASAAAAAEAAABIAAAAATAwMjA0ADIwMjY6MDY6MjYgMTc6NDI6NTUAAAqQAAAHAAAABDAyMjCQAwACAAAAFAAAATqQBAACAAAAFAAAAU6RAQAHAAAABAECAwCSfAAHAAAAUgAAAWKgAAAHAAAABDAxMDCgAQADAAAAAQABAACgAgAEAAAAAQAAAeCgAwAEAAAAAQAAAPCgBQAEAAAAAQAAAbQAAAAAMjAyNjowNjoyNiAxNzo0Mjo1NQAyMDI2OjA2OjI2IDE3OjQyOjU1AAABEQEABwAAAEAAAAF0AAAAADNEUzEBAAAAn3bRMQAAAAAEAgAAFAABAHhjG6oAAAAAAAAAAAAAAABGTPI/AAAAAIAEAAAAAAAAAAAAAAAAAAAAAwABAAIAAAAEUjk4AAACAAcAAAAEMDEwMBAAAAIAAAASAAAB3gAAAABKUEVHIEV4aWYgVmVyIDIuMgA=
    """

    static func timestamp(from uploadDate: String, defaultTime: String = defaultClockTime) -> String? {
        let clean = uploadDate.trimmingCharacters(in: .whitespacesAndNewlines)

        if clean.range(of: #"^\d{8}$"#, options: .regularExpression) != nil {
            let year = clean.prefix(4)
            let month = clean.dropFirst(4).prefix(2)
            let day = clean.dropFirst(6).prefix(2)
            return "\(year):\(month):\(day) \(defaultTime)"
        }

        if clean.range(of: #"^\d{4}[-:]\d{2}[-:]\d{2}$"#, options: .regularExpression) != nil {
            return "\(clean.replacingOccurrences(of: "-", with: ":")) \(defaultTime)"
        }

        if clean.range(of: #"^\d{4}:\d{2}:\d{2} \d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil {
            return clean
        }

        return nil
    }

    static func patch(aviURL: URL, timestamp: String) throws {
        var data = try Data(contentsOf: aviURL)
        let targetChunk = try firstMjpegChunk(in: data)

        if let existingRange = app1Range(in: data, chunk: targetChunk) {
            var app1 = Data(data[existingRange])
            try patchDates(in: &app1, timestamp: timestamp)
            data.replaceSubrange(existingRange, with: app1)
            try data.write(to: aviURL)
            return
        }

        let insertOffset = try app1InsertOffset(in: data, chunk: targetChunk)
        let dimensions = try avihDimensions(in: data)
        var app1 = try templateApp1()
        try patchDates(in: &app1, timestamp: timestamp)
        patchDimensions(in: &app1, width: dimensions.width, height: dimensions.height)

        let delta = app1.count
        data.insert(contentsOf: app1, at: insertOffset)

        try repairHeadersAndIndex(
            in: &data,
            delta: delta,
            firstChunk: targetChunk
        )

        try data.write(to: aviURL)
    }

    private static func templateApp1() throws -> Data {
        guard let data = Data(base64Encoded: templateApp1Base64) else {
            throw AVIDatePatcherError.invalidTemplate
        }
        return data
    }

    private static func firstMjpegChunk(in data: Data) throws -> RiffChunk {
        let moviMarker = try findMoviMarker(in: data)
        let idx1Offset = data.lastRange(of: Data("idx1".utf8))?.lowerBound ?? data.count
        var cursor = moviMarker + 4

        while cursor + 8 <= idx1Offset {
            let chunkID = Array(data[cursor ..< cursor + 4])
            let size = Int(data.u32LE(at: cursor + 4))
            let payloadOffset = cursor + 8
            let payloadEnd = payloadOffset + size

            if payloadEnd > data.count {
                break
            }

            if chunkID == Array("00dc".utf8),
               payloadOffset + 2 <= data.count,
               Array(data[payloadOffset ..< payloadOffset + 2]) == jpegSOI {
                return RiffChunk(
                    id: chunkID,
                    offset: cursor,
                    dataOffset: payloadOffset,
                    size: size
                )
            }

            cursor = payloadEnd
            if cursor.isMultiple(of: 2) == false {
                cursor += 1
            }
        }

        throw AVIDatePatcherError.firstVideoChunkNotFound
    }

    private static func app1Range(in data: Data, chunk: RiffChunk) -> Range<Int>? {
        let scanEnd = min(chunk.dataOffset + min(chunk.size, 1024), data.count)
        guard let markerRange = data.range(of: Data(app1Marker), in: chunk.dataOffset ..< scanEnd) else {
            return nil
        }

        guard markerRange.lowerBound + 4 <= data.count else {
            return nil
        }

        let length = Int(data.u16BE(at: markerRange.lowerBound + 2))
        let end = markerRange.lowerBound + 2 + length

        guard end <= chunk.dataOffset + chunk.size, end <= data.count else {
            return nil
        }

        return markerRange.lowerBound ..< end
    }

    private static func app1InsertOffset(in data: Data, chunk: RiffChunk) throws -> Int {
        guard chunk.dataOffset + 2 <= data.count,
              Array(data[chunk.dataOffset ..< chunk.dataOffset + 2]) == jpegSOI else {
            throw AVIDatePatcherError.invalidJPEG
        }

        var cursor = chunk.dataOffset + 2
        let chunkEnd = min(chunk.dataOffset + chunk.size, data.count)

        while cursor + 4 <= chunkEnd, data[cursor] == 0xFF {
            let markerByte = data[cursor + 1]
            if markerByte == 0xE1 {
                throw AVIDatePatcherError.app1AlreadyExists
            }

            let isAppMarker = (0xE0 ... 0xEF).contains(markerByte)
            let isComment = markerByte == 0xFE
            if !isAppMarker && !isComment {
                break
            }

            let length = Int(data.u16BE(at: cursor + 2))
            let segmentEnd = cursor + 2 + length
            if segmentEnd > chunkEnd {
                throw AVIDatePatcherError.truncatedJPEGSegment
            }

            cursor = segmentEnd
        }

        return cursor
    }

    private static func avihDimensions(in data: Data) throws -> (width: Int, height: Int) {
        guard let avihRange = data.range(of: Data("avih".utf8)) else {
            throw AVIDatePatcherError.avihNotFound
        }

        let payloadOffset = avihRange.lowerBound + 8
        guard payloadOffset + 40 <= data.count else {
            throw AVIDatePatcherError.avihNotFound
        }

        return (
            width: Int(data.u32LE(at: payloadOffset + 32)),
            height: Int(data.u32LE(at: payloadOffset + 36))
        )
    }

    private static func patchDates(in data: inout Data, timestamp: String) throws {
        let replacement = Array(timestamp.utf8)
        guard replacement.count == 19 else {
            throw AVIDatePatcherError.invalidTimestamp
        }

        var patchedCount = 0
        var cursor = 0
        while cursor + 19 <= data.count {
            if isDatePattern(Array(data[cursor ..< cursor + 19])) {
                data.replaceSubrange(cursor ..< cursor + 19, with: replacement)
                patchedCount += 1
                cursor += 19
            } else {
                cursor += 1
            }
        }

        if patchedCount == 0 {
            throw AVIDatePatcherError.templateDateNotFound
        }
    }

    private static func patchDimensions(in data: inout Data, width: Int, height: Int) {
        replaceSingleBigEndianU32(
            in: &data,
            oldValue: templateWidth,
            newValue: width
        )
        replaceSingleBigEndianU32(
            in: &data,
            oldValue: templateHeight,
            newValue: height
        )

        let oldSOF = Data([0x08, 0x00, 0xF0, 0x01, 0xE0])
        let newSOF = Data([
            0x08,
            UInt8((height >> 8) & 0xFF),
            UInt8(height & 0xFF),
            UInt8((width >> 8) & 0xFF),
            UInt8(width & 0xFF)
        ])

        if let range = data.range(of: oldSOF) {
            data.replaceSubrange(range, with: newSOF)
        }
    }

    private static func replaceSingleBigEndianU32(in data: inout Data, oldValue: Int, newValue: Int) {
        let oldBytes = Data([
            UInt8((oldValue >> 24) & 0xFF),
            UInt8((oldValue >> 16) & 0xFF),
            UInt8((oldValue >> 8) & 0xFF),
            UInt8(oldValue & 0xFF)
        ])
        let newBytes = Data([
            UInt8((newValue >> 24) & 0xFF),
            UInt8((newValue >> 16) & 0xFF),
            UInt8((newValue >> 8) & 0xFF),
            UInt8(newValue & 0xFF)
        ])

        if data.ranges(of: oldBytes).count == 1, let range = data.range(of: oldBytes) {
            data.replaceSubrange(range, with: newBytes)
        }
    }

    private static func repairHeadersAndIndex(
        in data: inout Data,
        delta: Int,
        firstChunk: RiffChunk
    ) throws {
        data.writeU32LE(data.u32LE(at: 4) + UInt32(delta), at: 4)

        let moviMarker = try findMoviMarker(in: data)
        data.writeU32LE(data.u32LE(at: moviMarker - 4) + UInt32(delta), at: moviMarker - 4)
        data.writeU32LE(UInt32(firstChunk.size + delta), at: firstChunk.offset + 4)

        guard let idx1Range = data.lastRange(of: Data("idx1".utf8)) else {
            return
        }

        let idx1 = idx1Range.lowerBound
        let idxSize = Int(data.u32LE(at: idx1 + 4))
        var cursor = idx1 + 8
        let end = min(cursor + idxSize, data.count)

        while cursor + 16 <= end {
            let chunkID = Array(data[cursor ..< cursor + 4])
            let offsetValue = data.u32LE(at: cursor + 8)
            let sizeValue = data.u32LE(at: cursor + 12)
            let absoluteOffset = moviMarker + Int(offsetValue)

            if absoluteOffset == firstChunk.offset, chunkID == firstChunk.id {
                data.writeU32LE(sizeValue + UInt32(delta), at: cursor + 12)
            } else if absoluteOffset > firstChunk.offset {
                data.writeU32LE(offsetValue + UInt32(delta), at: cursor + 8)
            }

            cursor += 16
        }
    }

    private static func findMoviMarker(in data: Data) throws -> Int {
        guard let range = data.range(of: Data("movi".utf8)) else {
            throw AVIDatePatcherError.moviNotFound
        }
        return range.lowerBound
    }

    private static func isDatePattern(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 19 else {
            return false
        }

        let separators: [Int: UInt8] = [
            4: 0x3A,
            7: 0x3A,
            10: 0x20,
            13: 0x3A,
            16: 0x3A
        ]

        for index in 0 ..< bytes.count {
            if let separator = separators[index] {
                if bytes[index] != separator {
                    return false
                }
            } else if !(0x30 ... 0x39).contains(bytes[index]) {
                return false
            }
        }

        return true
    }
}

private nonisolated struct RiffChunk {
    let id: [UInt8]
    let offset: Int
    let dataOffset: Int
    let size: Int
}

private nonisolated enum AVIDatePatcherError: LocalizedError {
    case invalidTemplate
    case invalidTimestamp
    case firstVideoChunkNotFound
    case invalidJPEG
    case app1AlreadyExists
    case truncatedJPEGSegment
    case avihNotFound
    case moviNotFound
    case templateDateNotFound

    var errorDescription: String? {
        switch self {
        case .invalidTemplate:
            return "Embedded 3DS Exif template could not be decoded."
        case .invalidTimestamp:
            return "3DS AVI timestamp must be exactly YYYY:MM:DD HH:MM:SS."
        case .firstVideoChunkNotFound:
            return "First MJPEG video chunk was not found in the AVI."
        case .invalidJPEG:
            return "First video chunk does not begin with a JPEG SOI marker."
        case .app1AlreadyExists:
            return "First video chunk already has an APP1 Exif segment."
        case .truncatedJPEGSegment:
            return "JPEG metadata segment is truncated."
        case .avihNotFound:
            return "AVI avih dimensions were not found."
        case .moviNotFound:
            return "AVI movi list was not found."
        case .templateDateNotFound:
            return "Embedded 3DS Exif template did not contain a timestamp."
        }
    }
}

private extension Data {
    nonisolated func u16BE(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8) |
        UInt16(self[offset + 1])
    }

    nonisolated func u32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset]) |
        (UInt32(self[offset + 1]) << 8) |
        (UInt32(self[offset + 2]) << 16) |
        (UInt32(self[offset + 3]) << 24)
    }

    nonisolated mutating func writeU32LE(_ value: UInt32, at offset: Int) {
        replaceSubrange(
            offset ..< offset + 4,
            with: [
                UInt8(value & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 24) & 0xFF)
            ]
        )
    }

    nonisolated func ranges(of needle: Data) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var searchStart = startIndex

        while searchStart < endIndex,
              let range = self.range(of: needle, in: searchStart ..< endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }

        return ranges
    }
}
