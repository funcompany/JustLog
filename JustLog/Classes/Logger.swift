//
//  Logger.swift
//  JustLog
//
//  Created by Alberto De Bortoli on 06/12/2016.
//  Copyright © 2017 Just Eat. All rights reserved.
//

import Foundation
import SwiftyBeaver

@objcMembers
public final class Logger: NSObject {
    
    internal enum LogType {
        case debug
        case warning
        case verbose
        case error
        case info
    }
    
    public var logTypeKey = "log_type"
    
    public var fileKey = "file"
    public var functionKey = "function"
    public var lineKey = "line"
    
    public var appVersionKey = "app_version"
    public var iosVersionKey = "ios_version"
    public var deviceTypeKey = "ios_device"
    
    public var errorDomain = "error_domain"
    public var errorCode = "error_code"

    public let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()

    public static let shared = Logger()
    
    // file conf
    public var logFilename: String?
    
    // logstash conf
    public var logstashHost: String!
    public var logstashPort: UInt16 = 9300
    public var logstashTimeout: TimeInterval = 20
    public var logLogstashSocketActivity: Bool = false
    public var logzioToken: String?

    /**
     Default to `false`, if `true` untrusted certificates (as self-signed are) will be trusted
     */
    public var allowUntrustedServer: Bool = false

    // logger conf
    public var defaultUserInfo: [String : Any]?
    public var enableConsoleLogging: Bool = true
    public var enableFileLogging: Bool = true
    public var enableLogstashLogging: Bool = true
    public var baseUrlForFileLogging = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    public let internalLogger = SwiftyBeaver.self
    private var dispatchTimer: Timer?
    
    // destinations
    public var console: ConsoleDestination!
    public var logstash: LogstashDestination!
    public var file: FileDestination!
    
    deinit {
        dispatchTimer?.invalidate()
        dispatchTimer = nil
    }
    
    public func setup() {
        
        let format = "$Dyyyy-MM-dd HH:mm:ss.SSS$d $T $C$L$c: $M"
        
        // console
        if enableConsoleLogging {
            console = JustLog.ConsoleDestination()
            console.format = format
            internalLogger.addDestination(console)
        }
        
        // file
        if enableFileLogging {
            file = JustLog.FileDestination()
            file.format = format
            if let baseURL = self.baseUrlForFileLogging {
                file.logFileURL = baseURL.appendingPathComponent(logFilename ?? "justeat.log", isDirectory: false)
            }
            internalLogger.addDestination(file)
        }
        
        // logstash
        if enableLogstashLogging {
            logstash = LogstashDestination(host: logstashHost, port: logstashPort, timeout: logstashTimeout, logActivity: logLogstashSocketActivity, allowUntrustedServer: allowUntrustedServer)
            logstash.logzioToken = logzioToken
            internalLogger.addDestination(logstash)
        }
        
        dispatchTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(scheduledForceSend(_:)), userInfo: nil, repeats: true)
    }
    
    public func forceSend(_ completionHandler: @escaping (_ error: Error?) -> Void = {_ in }) {
        if enableLogstashLogging {
            logstash.forceSend(completionHandler)
        }
    }
    
    public func cancelSending() {
        if enableLogstashLogging {
            logstash.cancelSending()
        }
    }
}

extension Logger: Logging {
    
    public func verbose(_ message: String, error: NSError?, userInfo: [String : Any]?, _ file: StaticString, _ function: StaticString, _ line: UInt) {
        let file = String(describing: file)
        let function = String(describing: function)
        log(.verbose, message, error: error, userInfo: userInfo, file, function, line)
    }
    
    public func debug(_ message: String, error: NSError?, userInfo: [String : Any]?, _ file: StaticString, _ function: StaticString, _ line: UInt) {
        let file = String(describing: file)
        let function = String(describing: function)
        log(.debug, message, error: error, userInfo: userInfo, file, function, line)
    }
    
    public func info(_ message: String, error: NSError?, userInfo: [String : Any]?, _ file: StaticString, _ function: StaticString, _ line: UInt) {
        let file = String(describing: file)
        let function = String(describing: function)
        log(.info, message, error: error, userInfo: userInfo, file, function, line)
    }
    
    public func warning(_ message: String, error: NSError?, userInfo: [String : Any]?, _ file: StaticString, _ function: StaticString, _ line: UInt) {
        let file = String(describing: file)
        let function = String(describing: function)
        log(.warning, message, error: error, userInfo: userInfo, file, function, line)

    }
    
    public func error(_ message: String, error: NSError?, userInfo: [String : Any]?, _ file: StaticString, _ function: StaticString, _ line: UInt) {
        let file = String(describing: file)
        let function = String(describing: function)
        log(.error, message, error: error, userInfo: userInfo, file, function, line)
    }
    
    internal func log(_ type: LogType, _ message: String, error: NSError?, userInfo: [String : Any]?, _ file: String, _ function: String, _ line: UInt) {
        let messageToLog = logMessage(message, error: error, userInfo: userInfo, file, function, line)
        sendLogMessage(with: type, logMessage: messageToLog, file, function, line)
    }
    
    internal func sendLogMessage(with type: LogType, logMessage: String, _ file: String, _ function: String, _ line: UInt) {
        switch type {
        case .error:
            internalLogger.error(logMessage, file, function, line: Int(line))
        case .warning:
            internalLogger.warning(logMessage, file, function, line: Int(line))
        case .debug:
            internalLogger.debug(logMessage, file, function, line: Int(line))
        case .info:
            internalLogger.info(logMessage, file, function, line: Int(line))
        case .verbose:
            internalLogger.verbose(logMessage, file, function, line: Int(line))
        }
    }
}

extension Logger {
    
    internal func logMessage(_ message: String, error: NSError?, userInfo: [String : Any]?, _ file: String, _ function: String, _ line: UInt) -> String {
    
        let messageConst = "message"
        let userInfoConst = "dynamic"
        let metadataConst = "metadata"
        let errorsConst = "errors"
        let timeConst = "@timestamp"
        
        var retVal = defaultUserInfo ?? [String : Any]()
        
        var skData = [String: Any]()
        var b4cClient = [String: Any]()
        retVal[messageConst] = message
        b4cClient[metadataConst] = metadataDictionary(file, function, line)
        retVal[timeConst] = timestampFormatter.string(from: Date())
        retVal[userInfoConst] = userInfo

        if let error = error {
            b4cClient[errorsConst] = error.disassociatedErrorChain().map( { return jsonify(object: $0) } )
        }
        skData["b4cClient"] = b4cClient
        retVal["skData"] = skData

        do {
            return try JSONSerialization.data(withJSONObject: jsonify(object: retVal)).stringRepresentation()
        } catch {
            let error = error as NSError
            return """
                    {
                        "skData": {
                            "b4cClient": {
                                "\(errorsConst)": [
                                    {
                                        "domain": \(error.domain),
                                        "code": \(error.code),
                                        "userInfo": {
                                            "NSLocalizedDescriptionKey": "\(error.localizedDescription)"
                                        }
                                    }
                                ]
                            }
                        }
                    }
                   """

        }
    }
    
    private func metadataDictionary(_ file: String, _ function: String, _ line: UInt) -> [String: Any] {
        var fileMetadata = [String : String]()
        
        if let url = URL(string: file) {
            fileMetadata[fileKey] = URLComponents(url: url, resolvingAgainstBaseURL: false)?.url?.pathComponents.last ?? file
        }
        
        fileMetadata[functionKey] = function
        fileMetadata[lineKey] = String(line)
        
        if let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"], let bundleShortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] {
            fileMetadata[appVersionKey] = "\(bundleShortVersion) (\(bundleVersion))"
        }
        
        fileMetadata[iosVersionKey] = UIDevice.current.systemVersion
        fileMetadata[deviceTypeKey] = UIDevice.current.platform()
        
        return fileMetadata
    }
    
    internal func errorDictionary(for error: NSError) -> [String : Any] {
        let userInfoConst = "user_info"
        var errorInfo = [errorDomain: error.domain,
                         errorCode: error.code] as [String : Any]
        let errorUserInfo = error.humanReadableError().userInfo
        errorInfo[userInfoConst] = errorUserInfo
        return errorInfo
    }
    
    @objc fileprivate func scheduledForceSend(_ timer: Timer) {
        forceSend()
    }

}

fileprivate func jsonify(object: Any?) -> Any {
    guard let object = object else {
        return NSNull()
    }
    if JSONSerialization.isValidJSONObject(object) {
        return object
    }
    if let dict = object as? [AnyHashable: Any] {
        var newDict = [String: Any]()
        for (key, value) in dict {
            newDict[String(describing: key)] = jsonify(object: value)
        }
        return newDict
    }
    if let sequence = object as? AnySequence<Any> {
        var array = [Any]()
        for value in sequence {
            array.append(jsonify(object: value))
        }
        return array
    }
    if let error = object as? NSError {
        var errDict = [String: Any]()
        errDict["domain"] = error.domain
        errDict["code"] = error.code
        errDict["userInfo"] = jsonify(object: error.userInfo)
        return errDict
    }
    // Ultimate fallback - string representation. May not be accurate but never fails.
    return String(describing: object)
}
