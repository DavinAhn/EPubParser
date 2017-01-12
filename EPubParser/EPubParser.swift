//
//  EPubParser.swift
//  EPubParser
//
//  Created by Davin Ahn on 2017. 1. 8..
//  Copyright © 2017년 Davin Ahn. All rights reserved.
//

public class EPubParserConfiguration {
    internal init() {}
    
    // If true, check the package specifications for the IDPF listed below.
    // - The Zip header should not corrupt.
    // - The mimetype file must be the first file in the archive.
    // - The mimetype file should not compressed.
    // - The mimetype file should only contain the string 'application/epub+zip'.
    // - Should not use extra field feature of the ZIP format for the mimetype file.
    public var shouldValidatePackage = false
}

public class EPubParser {
    internal let configuration: EPubParserConfiguration
    
    private init(configuration: EPubParserConfiguration = EPubParserConfiguration()) {
        self.configuration = configuration
    }
    
    public class func configuration(_ configuration: (EPubParserConfiguration) -> ()) -> EPubParser {
        let config = EPubParserConfiguration()
        configuration(config)
        return EPubParser(configuration: config)
    }
    
    public func parseAt(_ path: String, password: String?, toPath: String? = nil) {
        var entries = [String]()
        do {
            if configuration.shouldValidatePackage {
                try EPubHelper.validateZipAt(path)
            }
            if let toPath = toPath {
                entries += try EPubHelper.unzipAt(path, toPath: toPath, password: password)
            } else {
                entries += try EPubHelper.entriesOfZipAt(path, password: password)
            }
        } catch {  }
    }
}
