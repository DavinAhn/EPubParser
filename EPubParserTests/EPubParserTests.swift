//
//  EPubParserTests.swift
//  EPubParserTests
//
//  Created by DaVin Ahn on 2017. 1. 8..
//  Copyright © 2017년 Davin Ahn. All rights reserved.
//

import XCTest
@testable import EPubParser

class EPubParserTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func documentPath() -> String {
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    }
    
    func testUnzip() {
        let path1 = "Sample.epub"
        do {
            _ = try EPubHelper.entriesOfZipAt(path1, password: nil)
        } catch UnzipError.fileNotFound(let path) {
            XCTAssertTrue(path1 == path)
        } catch {
            XCTFail()
        }
        
        let path2 = Bundle(for: self.classForCoder).path(forResource: "Sample", ofType: "epub")!
        do {
            let results = [
                "mimetype",
                "META-INF/container.xml",
                "OEBPS/content.opf",
                "OEBPS/Text/Section0001.xhtml",
                "OEBPS/toc.ncx"
            ]
            let entries = try EPubHelper.entriesOfZipAt(path2, password: nil)
            XCTAssertTrue(!entries.isEmpty && entries.count == results.count)
            for i in 0..<results.count {
                XCTAssertTrue(entries[i] == results[i])
            }
            
            let data = try EPubHelper.dataOf("mimetype", atZipPath: path2, password: nil)
            XCTAssertTrue(String(data: data, encoding: String.Encoding.ascii)! == "application/epub+zip")
            
            _ = try EPubHelper.dataOf("OEBPS", atZipPath: path2, password: nil)
        } catch UnzipError.fileNotFound(let path) {
            XCTAssertTrue("OEBPS" == path)
        } catch {
            XCTFail()
        }
        
        do {
            try EPubHelper.validateZipAt(path2)
        } catch {
            XCTFail()
        }
        
        let url1 = Bundle(for: self.classForCoder).url(forResource: "Sample", withExtension: "cbz")!
        do {
            _ = try EPubHelper.entriesOfZipAt(url1, password: nil)
        } catch UnzipError.fileNotSupport(let path) {
            XCTAssertTrue(url1.path == path)
        } catch {
            XCTFail()
        }
        
        let url2 = URL(string: "https://github.com/DaVinAhn/EPubParser")!
        do {
            _ = try EPubHelper.entriesOfZipAt(url2, password: nil)
        } catch UnzipError.notFile(let url) {
            XCTAssertTrue(url2 == url)
        } catch {
            XCTFail()
        }
        
        let toPath = documentPath().appendingPathComponent("sample")
        do {
            let entries = try EPubHelper.unzipAt(path2, toPath: toPath, password: nil)
            for entry in entries {
                XCTAssertTrue(FileManager.default.fileExists(atPath: toPath.appendingPathComponent(entry)))
            }
        } catch {
            XCTFail()
        }
    }
}
