//
//  DocumentEditView.swift
//  Quarry
//
//  Created by Fauzaan on 3/30/25.
//
import SwiftUI
import MongoKitten
import LanguageSupport

struct DocumentEditView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var editingDocumentJSON: String

    @State private var isHovered: Bool = false
    @State private var position: CodeEditor.Position = CodeEditor.Position()

    init(editingJSON: Binding<String>) {
        _editingDocumentJSON = editingJSON
    }
    
    var body: some View {
        CodeEditor(
            text: $editingDocumentJSON,
            position: $position,
            messages: .constant(Set()),
            language: .mongodb()
        )
        .environment(\.codeEditorTheme, colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
        .environment(\.codeEditorLayoutConfiguration, .init(wrapText: true, dynamicHeight: true))
        .cornerRadius(10)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
}
