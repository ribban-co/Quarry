//
//  String.swift
//  Collection
//
//  Created by Fauzaan on 2/13/25.
//

extension String {
    func matches(searchText: String?) -> Bool {
        guard let searchText = searchText, !searchText.isEmpty else { return true }
        return self.localizedCaseInsensitiveContains(searchText)
    }
}
