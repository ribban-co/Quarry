//
//  JSON+Decoder.swift
//  Quarry
//
//  Created by Fauzaan on 4/8/25.
//

import Foundation
import yyjson

struct JSONDecoder {
    private let data: Data
    private var parsedResult: Any?
    private var error: Error?
    
    init(data: Data) {
        self.data = data
        do {
            self.parsedResult = try parseJSON(data)
        } catch let err {
            self.error = err
        }
    }
    
    func json() throws -> Any {
        if let error = error {
            throw error
        }
        
        if let result = parsedResult {
            return result
        }
        
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "Failed to parse JSON"
            )
        )
    }
    
    func jsonKeyValuePairs() throws -> [(key: String, value: Any)] {
        if let error = error {
            throw error
        }
        
        if let tuples = parsedResult as? [(key: String, value: Any)] {
            return tuples
        } else if let dict = parsedResult as? [String: Any] {
            // Convert dictionary to array of key-value pairs (order not preserved)
            return dict.map { (key: $0.key, value: $0.value) }
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Root is not a JSON object"
                )
            )
        }
    }
    
    private func parseJSON(_ data: Data) throws -> Any {
        return try data.withUnsafeBytes { rawBufferPointer -> Any in
            guard let baseAddress = rawBufferPointer.baseAddress else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "Could not access data buffer"
                    )
                )
            }
            
            // Parse JSON
            guard let doc = yyjson_read(baseAddress, size_t(data.count), 0) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "Failed to parse JSON"
                    )
                )
            }
            defer { yyjson_doc_free(doc) }
            
            // Get root
            guard let root = yyjson_doc_get_root(doc) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "Failed to get root value"
                    )
                )
            }
            
            return convertYYJSONToSwift(root)
        }
    }
    
    private func convertYYJSONToSwift(_ jsonVal: UnsafeMutablePointer<yyjson_val>?) -> Any {
        guard let jsonVal = jsonVal else {
            return NSNull()
        }
        
        if yyjson_is_null(jsonVal) {
            return NSNull()
        } else if yyjson_is_bool(jsonVal) {
            return yyjson_get_bool(jsonVal)
        } else if yyjson_is_int(jsonVal) {
            if yyjson_is_uint(jsonVal) {
                return yyjson_get_uint(jsonVal)
            } else {
                return yyjson_get_sint(jsonVal)
            }
        } else if yyjson_is_real(jsonVal) {
            return yyjson_get_real(jsonVal)
        } else if yyjson_is_str(jsonVal) {
            guard let cStr = yyjson_get_str(jsonVal) else {
                return ""
            }
            return String(cString: cStr)
        } else if yyjson_is_arr(jsonVal) {
            var array: [Any] = []
            
            var iter = yyjson_arr_iter()
            yyjson_arr_iter_init(jsonVal, &iter)
            
            while let val = yyjson_arr_iter_next(&iter) {
                array.append(convertYYJSONToSwift(val))
            }
            
            return array
        } else if yyjson_is_obj(jsonVal) {
            // Use an array to preserve key order
            var keyValuePairs: [(key: String, value: Any)] = []
            
            var iter = yyjson_obj_iter()
            yyjson_obj_iter_init(jsonVal, &iter)
            
            while let key = yyjson_obj_iter_next(&iter) {
                guard let keyStr = yyjson_get_str(key) else {
                    continue
                }
                
                let val = yyjson_obj_iter_get_val(key)
                let keyString = String(cString: keyStr)
                let valueAny = convertYYJSONToSwift(val)
                
                keyValuePairs.append((key: keyString, value: valueAny))
            }
            
            // For compatibility with existing code, return a dictionary
            // But for order-preservation, use the jsonKeyValuePairs() method
            return keyValuePairs
        }
        
        return NSNull()
    }
}
