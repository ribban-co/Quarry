//
//  NotebookEditorStubView.swift
//  Quarry
//

import SwiftUI
import SwiftData

struct NotebookEditorStubView: View {
    let notebookId: UUID

    @Query private var notebooks: [Notebook]

    private var notebook: Notebook? {
        notebooks.first { $0.id == notebookId }
    }

    var body: some View {
        VStack(spacing: 16) {
            if let notebook {
                Image(systemName: "doc.text")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text(notebook.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("The notebook editor is coming soon.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.brand)

                Text("Notebook Not Found")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
