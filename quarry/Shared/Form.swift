//
//  Form.swift
//  Collection
//
//  Created by Fauzaan on 2/5/25.
//

import SwiftUI

struct FormField<Content: View>: View {
    let label: String
    let content: Content
    var errorMessage: String? = nil
    var highlight: Color? = nil
    
    init(label: String, errorMessage: String? = nil, highlight: Color? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
        self.errorMessage = errorMessage
        self.highlight = highlight
    }
    
    var body: some View {
           VStack(alignment: .leading, spacing: 6) {
               HStack {
                   Text(label)
                       .foregroundColor(.secondary)
                       .font(.system(size: 13))
                   
                   Spacer()
                   
                   if let errorMessage = errorMessage, !errorMessage.isEmpty {
                       Text(errorMessage)
                           .foregroundColor(.red)
                           .font(.system(size: 12))
                   }
               }
               .padding(.leading, 2)
               
               content
                   .background(
                       RoundedRectangle(cornerRadius: 10)
                           .fill(highlight ?? Color.clear)
                           .opacity(highlight == nil ? 0 : 0.17)
                           .animation(.easeInOut(duration: 0.15), value: highlight == nil)
                   )
           }
       }
}
