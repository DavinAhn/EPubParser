//
//  EPubHelper.swift
//  EPubParser
//
//  Created by Davin Ahn on 2017. 1. 8..
//  Copyright © 2017년 Davin Ahn. All rights reserved.
//

import Foundation
import minizip

public enum UnzipError: Error {
    case notFile(url: URL)
    case notDirectory(path: String)
    case alreadyExistsDirectory(path: String)
    case fileNotFound(path: String)
    case fileNotSupport(path: String)
    case openFail(path: String)
    case unzipFail(path: String)
    case crcError(path: String)
    case encodingError(path: String)
    case invalidPackaging(path: String)
}

fileprivate struct UnzipOptionKey: RawRepresentable, Hashable {
    fileprivate var rawValue: String
    
    fileprivate var hashValue: Int {
        return rawValue.hash
    }
    
    fileprivate static let toPath = UnzipOptionKey(rawValue: "toPath")
    fileprivate static let overwrite = UnzipOptionKey(rawValue: "overwrite")
    fileprivate static let checkCrc = UnzipOptionKey(rawValue: "checkCrc")
}

internal extension String {
    private var nsString: NSString {
        return (self as NSString)
    }
    
    var lastPathComponent: String {
        return nsString.lastPathComponent
    }
    
    var pathExtension: String {
        return nsString.pathExtension
    }
    
    var deletingLastPathComponent: String {
        return nsString.deletingLastPathComponent
    }
    
    var deletingPathExtension: String {
        return nsString.deletingPathExtension
    }
    
    var pathComponents: [String] {
        return nsString.pathComponents
    }
    
    func appendingPathComponent(_ str: String) -> String {
        return nsString.appendingPathComponent(str)
    }
    
    func appendingPathExtension(_ str: String) -> String? {
        return nsString.appendingPathExtension(str)
    }
}

fileprivate extension Date {
    static func dateFrom(tmuDate: tm_unz_s) -> Date {
        var dateComponents = DateComponents()
        dateComponents.second = Int(tmuDate.tm_sec)
        dateComponents.minute = Int(tmuDate.tm_min)
        dateComponents.hour = Int(tmuDate.tm_hour)
        dateComponents.day = Int(tmuDate.tm_mday)
        dateComponents.month = Int(tmuDate.tm_mon) + 1
        dateComponents.year = Int(tmuDate.tm_year)
        let calendar = Calendar.current
        return calendar.date(from: dateComponents) ?? Date()
    }
}

internal class EPubHelper {
    fileprivate static var supportedZipExtensions = ["epub", "zip"]
    fileprivate static var unzipBufferSize: UInt32 = 4096
    fileprivate static var zipHeaderSize = 58
    
    internal class func validateZipAt(_ path: String) throws {
        try validateZipAt(URL(fileURLWithPath: path))
    }
    
    internal class func validateZipAt(_ url: URL) throws {
        if !url.isFileURL {
            throw UnzipError.notFile(url: url)
        }
        
        let fileManager = FileManager.default
        let path = url.path
        
        if !fileManager.fileExists(atPath: path) {
            throw UnzipError.fileNotFound(path: path)
        }
        
        if !supportedZipExtensions.contains(path.pathExtension.lowercased()) {
            throw UnzipError.fileNotSupport(path: path)
        }
        
        guard let data = try? Data(contentsOf: url), data.count >= zipHeaderSize else {
            throw UnzipError.openFail(path: path)
        }
        let bytes = [UInt8](data)
        let fileSignature = String(bytes: bytes[0..<2], encoding: String.Encoding.ascii)
        let fileNameSize = UInt32(littleEndian: Data(bytes: bytes[26..<28]).withUnsafeBytes { $0.pointee })
        let extraFieldSize = UInt32(littleEndian: Data(bytes: bytes[28..<30]).withUnsafeBytes { $0.pointee })
        let fileName = String(bytes: bytes[30..<38], encoding: String.Encoding.ascii)
        let mimetype = String(bytes: bytes[38..<zipHeaderSize], encoding: String.Encoding.ascii)
        
        if fileSignature != "PK"
            || fileNameSize != 8
            || extraFieldSize != 0
            || fileName != "mimetype"
            || mimetype != "application/epub+zip" {
            throw UnzipError.invalidPackaging(path: path)
        }
    }
    
    internal class func entriesOfZipAt(_ url: URL, password: String?) throws -> [String] {
        if !url.isFileURL {
            throw UnzipError.notFile(url: url)
        }
        return try entriesOfZipAt(url.path, password: password)
    }
    
    internal class func entriesOfZipAt(_ path: String, password: String?) throws -> [String] {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: path) {
            throw UnzipError.fileNotFound(path: path)
        }
        
        if !supportedZipExtensions.contains(path.pathExtension.lowercased()) {
            throw UnzipError.fileNotSupport(path: path)
        }
        
        return try unzipAt(path, password: password, options: [
            UnzipOptionKey.checkCrc: false
        ])
    }
    
    internal class func dataOf(_ entryPath: String, atZipPath zipPath: String, password: String?) throws -> Data {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: zipPath) {
            throw UnzipError.fileNotFound(path: zipPath)
        }
        
        if !supportedZipExtensions.contains(zipPath.pathExtension.lowercased()) {
            throw UnzipError.fileNotSupport(path: zipPath)
        }
        
        guard let zip = unzOpen64(zipPath) else {
            throw UnzipError.openFail(path: zipPath)
        }
        defer { unzClose(zip) }
        if unzGoToFirstFile(zip) != UNZ_OK {
            throw UnzipError.openFail(path: zipPath)
        }
        
        guard let path = entryPath.cString(using: String.Encoding.ascii) else {
            throw UnzipError.encodingError(path: entryPath)
        }
        var ret = unzLocateFile(zip, path) { (_, fileName1, fileName2) -> Int32 in
            return strcasecmp(fileName1, fileName2)
        }
        if ret != UNZ_OK {
            throw UnzipError.fileNotFound(path: entryPath)
        }
        
        if let password = password?.cString(using: String.Encoding.ascii) {
            ret = unzOpenCurrentFilePassword(zip, password)
        } else {
            ret = unzOpenCurrentFile(zip)
        }
        if ret != UNZ_OK {
            throw UnzipError.unzipFail(path: entryPath)
        }
        
        let data = NSMutableData()
        var buffer = Array<CUnsignedChar>(repeating: 0, count: Int(unzipBufferSize))
        repeat {
            let readBytes = Int(unzReadCurrentFile(zip, &buffer, unzipBufferSize))
            if readBytes > 0 {
                data.append(buffer, length: readBytes)
            } else {
                break
            }
        } while true
        unzCloseCurrentFile(zip)
        
        return data as Data
    }
    
    internal class func unzipAt(_ url: URL, to: URL, password: String?, overwrite: Bool = true) throws -> [String] {
        if !url.isFileURL {
            throw UnzipError.notFile(url: url)
        } else if !to.isFileURL {
            throw UnzipError.notFile(url: to)
        }
        return try unzipAt(url.path, toPath: to.path, password: password, overwrite: overwrite)
    }
    
    internal class func unzipAt(_ path: String, toPath: String, password: String?, overwrite: Bool = true) throws -> [String] {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: path) {
            throw UnzipError.fileNotFound(path: path)
        }
        
        if !supportedZipExtensions.contains(path.pathExtension.lowercased()) {
            throw UnzipError.fileNotSupport(path: path)
        }
        
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: toPath, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                throw UnzipError.notDirectory(path: toPath)
            } else if overwrite {
                try fileManager.removeItem(atPath: toPath)
            } else {
                throw UnzipError.alreadyExistsDirectory(path: toPath)
            }
        } else {
            try fileManager.createDirectory(atPath: toPath, withIntermediateDirectories: true, attributes: nil)
        }
        
        return try unzipAt(path, password: password, options: [
            UnzipOptionKey.toPath: toPath,
            UnzipOptionKey.overwrite: overwrite
        ])
    }
    
    fileprivate class func unzipAt(_ path: String, password: String?, options: [UnzipOptionKey: Any]) throws -> [String] {
        guard let zip = unzOpen64(path) else {
            throw UnzipError.openFail(path: path)
        }
        defer { unzClose(zip) }
        if unzGoToFirstFile(zip) != UNZ_OK {
            throw UnzipError.openFail(path: path)
        }
        
        let fileManager = FileManager.default
        let toPath = options[.toPath] as? String ?? ""
        let overwrite = options[.overwrite] as? Bool ?? true
        let checkCrc = options[.checkCrc] as? Bool ?? true
        let readOnly = toPath.isEmpty
        
        var ret: Int32 = 0
        var buffer = Array<CUnsignedChar>(repeating: 0, count: Int(unzipBufferSize))
        var entries = [String]()
        repeat {
            if let password = password?.cString(using: String.Encoding.ascii) {
                ret = unzOpenCurrentFilePassword(zip, password)
            } else {
                ret = unzOpenCurrentFile(zip)
            }
            if ret != UNZ_OK {
                throw UnzipError.unzipFail(path: path)
            }
            
            var fileInfo = unz_file_info64()
            memset(&fileInfo, 0, MemoryLayout<unz_file_info>.size)
            ret = unzGetCurrentFileInfo64(zip, &fileInfo, nil, 0, nil, 0, nil, 0)
            if ret != UNZ_OK {
                unzCloseCurrentFile(zip)
                throw UnzipError.unzipFail(path: path)
            }
            
            let fileNameSize = Int(fileInfo.size_filename) + 1
            let fileName = UnsafeMutablePointer<CChar>.allocate(capacity: fileNameSize)
            unzGetCurrentFileInfo64(zip, &fileInfo, fileName, UInt(fileNameSize), nil, 0, nil, 0)
            fileName[Int(fileInfo.size_filename)] = 0
            
            var entryPath = String(cString: fileName)
            if entryPath.characters.isEmpty {
                unzCloseCurrentFile(zip)
                throw UnzipError.unzipFail(path: path)
            }
            
            var isDirectory = false
            let fileInfoSize = Int(fileInfo.size_filename - 1)
            if (fileName[fileInfoSize] == "/".cString(using: String.Encoding.utf8)?.first
                || fileName[fileInfoSize] == "\\".cString(using: String.Encoding.utf8)?.first) {
                isDirectory = true
            }
            free(fileName)
            if entryPath.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\")) != nil {
                entryPath = entryPath.replacingOccurrences(of: "\\", with: "/")
            }
            
            let fullPath = toPath.appendingPathComponent(entryPath)
            entries.append(entryPath)
            if readOnly {
                let crc_ret = unzCloseCurrentFile(zip)
                if checkCrc && crc_ret == UNZ_CRCERROR {
                    throw UnzipError.crcError(path: path)
                }
                ret = unzGoToNextFile(zip)
                continue
            }
            
            do {
                if isDirectory {
                    try fileManager.createDirectory(atPath: fullPath, withIntermediateDirectories: true, attributes: nil)
                } else {
                    try fileManager.createDirectory(atPath: fullPath.deletingLastPathComponent, withIntermediateDirectories: true, attributes: nil)
                }
            } catch {}
            
            if fileManager.fileExists(atPath: fullPath) && !isDirectory && !overwrite {
                unzCloseCurrentFile(zip)
                ret = unzGoToNextFile(zip)
            }
            
            let file = fopen(fullPath, "wb")
            while file != nil {
                let readBytes = unzReadCurrentFile(zip, &buffer, unzipBufferSize)
                if readBytes > 0 {
                    fwrite(buffer, Int(readBytes), 1, file)
                } else {
                    break
                }
            }
            if file != nil {
                fclose(file)
                if fileInfo.dosDate != 0 {
                    let originDate = Date.dateFrom(tmuDate: fileInfo.tmu_date)
                    do {
                        let attr = [FileAttributeKey.modificationDate: originDate]
                        try fileManager.setAttributes(attr, ofItemAtPath: fullPath)
                    } catch {}
                }
            }
            
            let crc_ret = unzCloseCurrentFile(zip)
            if checkCrc && crc_ret == UNZ_CRCERROR {
                throw UnzipError.crcError(path: path)
            }
            ret = unzGoToNextFile(zip)
        } while (ret == UNZ_OK && ret != UNZ_END_OF_LIST_OF_FILE)
        
        return entries
    }
}
