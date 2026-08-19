//
//  NotebookCard.swift
//  Quarry
//

import SwiftUI

struct NotebookIcon: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(red: 0.6, green: 0.4, blue: 0.1))
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "doc.text")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
            )
    }
}

struct NotebookStatusTag: View {
    let status: NotebookStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(status.color.opacity(0.75), lineWidth: 1)
            )
    }
}
