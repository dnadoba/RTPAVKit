//
//  File.swift
//  
//
//  Created by David Nadoba on 20.04.20.
//

import Foundation

fileprivate enum ApplePlatform {
    case macOS
    case tvOS
    case iOS
    case watchOS
    case unkown
}

extension ApplePlatform {
    static var current: Self {
        #if os(macOS)
        return .macOS
        #elseif os(tvOS)
        return .tvOS
        #elseif os(iOS)
        return .iOS
        #elseif os(watchOS)
        return .watchOS
        #else
        return .unkown
        #endif
    }
}

struct OSStatusError: Error {
    var osStatus: OSStatus
    var description: String?
    init(_ osStatus: OSStatus, description: String? = nil) {
        self.osStatus = osStatus
        self.description = description
    }
    var osStatusLookupURL: String {
        "https://www.osstatus.com/search/results?platform=all&framework=all&search=\(osStatus)"
    }
    var osStatusDescription: String {
        "OSStatus = \(osStatus) - \(osStatusLookupURL)"
    }
    var localizedDescription: String {
        if let description = description {
            return "\(description) - \(osStatusDescription)"
        } else {
            return osStatusDescription
        }
    }
}

extension OSStatusError {
    static func check(_ osStatus: OSStatus, errorDescription: @autoclosure () -> String? = nil) throws {
        guard osStatus == kOSReturnSuccess else {
            throw OSStatusError(osStatus, description: errorDescription())
        }
    }
}
