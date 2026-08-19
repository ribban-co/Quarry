//
//  DocumentListModel.swift
//  Collection
//
//  Created by Fauzaan on 2/19/25.
//

import Foundation

class PaginationManager {
    private(set) var currentPage: Int
    private(set) var rowsPerPage: Int
    private(set) var totalRows: Int
    
    var totalPages: Int {
        return max(1, Int(ceil(Double(totalRows) / Double(rowsPerPage))))
    }
    
    init(rowsPerPage: Int = 300) {
        self.currentPage = 1
        self.rowsPerPage = rowsPerPage
        self.totalRows = 0
    }
    
    func updateTotalItems(_ count: Int) {
        self.totalRows = count
    }
    
    func nextPage() -> Bool {
        currentPage += 1
        return true
    }
    
    func previousPage() -> Bool {
        guard currentPage > 1 else { return false }
        currentPage -= 1
        return true
    }
    
    func goToPage(_ page: Int) -> Bool {
        guard page >= 1 && page <= totalPages else { return false }
        currentPage = page
        return true
    }
    
    var skip: Int {
        return (currentPage - 1) * rowsPerPage
    }
    
    var limit: Int {
        return rowsPerPage
    }
} 
