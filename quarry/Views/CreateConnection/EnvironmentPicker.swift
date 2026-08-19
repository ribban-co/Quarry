//
//  ConnectionColorPicker.swift
//  Collection
//
//  Created by Fauzaan on 2/1/25.
//
import SwiftUI

struct EnvironmentPicker: View {
    @Binding var selectedEnvironment: ConnectionEnvironment?
    
    var body: some View {
        FormField(label: "Environment") {
            Menu {
                ForEach(ConnectionEnvironment.allCases, id: \.self) { env in
                    Button(action: {
                        selectedEnvironment = env
                    }) {
                        Text(env.rawValue)
                    }
                }
            } label: {
                Text(selectedEnvironment?.rawValue ?? "Select Environment")
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "chevron.compact.down")
                    .scaleEffect(CGSize(width: 0.7, height: 1.5))
            }
            .menuStyle(.button)
            .buttonStyle(CustomMenuButtonStyle())
            
        }
    }
}
