//
//  TextField.swift
//  Collection
//
//  Created by Fauzaan on 2/8/25.
//

import SwiftUI

struct CustomTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                       (colorScheme == .dark ? Color.black : Color.white)
                           .opacity(isFocused ? 0.2 : 0.0)
                   )
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator, lineWidth: 1)
            )
            .focused($isFocused)
        
    }
}

struct TextEditorWithPlaceholder: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var isFocused: Bool
    var height: CGFloat = 120
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color.black.opacity(isFocused ? 0.2 : 0))
                .foregroundColor(.white)
                .focused($isFocused)
            
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: height)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }
}

struct FilterTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.controlColor).opacity(isFocused ? 0.2 : 0))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.separator)
            )
            .cornerRadius(6)
            .focused($isFocused)
        
    }
}


extension String {
    var sentenceCase: String {
        guard !isEmpty else { return self }
        return prefix(1).uppercased() + dropFirst().lowercased()
    }
}
