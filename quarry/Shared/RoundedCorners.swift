//
//  CustomRounded.swift
//  Quarry
//
//  Created by Fauzaan on 4/20/25.
//

import SwiftUI

struct RoundedCorners: Shape {
    var tl: CGFloat = 0.0
    var tr: CGFloat = 0.0
    var bl: CGFloat = 0.0
    var br: CGFloat = 0.0
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.size.width
        let height = rect.size.height
        
        // Top left corner
        path.move(to: CGPoint(x: 0, y: tl))
        path.addArc(center: CGPoint(x: tl, y: tl),
                   radius: tl,
                   startAngle: Angle(degrees: 180),
                   endAngle: Angle(degrees: 270),
                   clockwise: false)
        
        // Top right corner
        path.addLine(to: CGPoint(x: width - tr, y: 0))
        path.addArc(center: CGPoint(x: width - tr, y: tr),
                   radius: tr,
                   startAngle: Angle(degrees: 270),
                   endAngle: Angle(degrees: 0),
                   clockwise: false)
        
        // Bottom right corner
        path.addLine(to: CGPoint(x: width, y: height - br))
        if br > 0 {
            path.addArc(center: CGPoint(x: width - br, y: height - br),
                       radius: br,
                       startAngle: Angle(degrees: 0),
                       endAngle: Angle(degrees: 90),
                       clockwise: false)
        } else {
            path.addLine(to: CGPoint(x: width, y: height))
        }
        
        // Bottom left corner
        path.addLine(to: CGPoint(x: bl, y: height))
        if bl > 0 {
            path.addArc(center: CGPoint(x: bl, y: height - bl),
                       radius: bl,
                       startAngle: Angle(degrees: 90),
                       endAngle: Angle(degrees: 180),
                       clockwise: false)
        } else {
            path.addLine(to: CGPoint(x: 0, y: height))
        }
        
        path.closeSubpath()
        return path
    }
}

struct RoundedCornersTop: Shape {
    var tl: CGFloat = 0.0
    var tr: CGFloat = 0.0
    var bl: CGFloat = 0.0
    var br: CGFloat = 0.0
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.size.width
        let height = rect.size.height
        
        // Start from bottom left (no bottom line will be drawn)
        path.move(to: CGPoint(x: 0, y: height))
        
        // Left side to top left corner
        if tl > 0 {
            path.addLine(to: CGPoint(x: 0, y: tl))
            path.addArc(center: CGPoint(x: tl, y: tl),
                       radius: tl,
                       startAngle: Angle(degrees: 180),
                       endAngle: Angle(degrees: 270),
                       clockwise: false)
        } else {
            path.addLine(to: CGPoint(x: 0, y: 0))
        }
        
        // Top edge to top right corner
        path.addLine(to: CGPoint(x: width - tr, y: 0))
        if tr > 0 {
            path.addArc(center: CGPoint(x: width - tr, y: tr),
                       radius: tr,
                       startAngle: Angle(degrees: 270),
                       endAngle: Angle(degrees: 0),
                       clockwise: false)
        } else {
            path.addLine(to: CGPoint(x: width, y: 0))
        }
        
        // Right side down to bottom right corner
        if br > 0 {
            path.addLine(to: CGPoint(x: width, y: height - br))
            path.addArc(center: CGPoint(x: width - br, y: height - br),
                       radius: br,
                       startAngle: Angle(degrees: 0),
                       endAngle: Angle(degrees: 90),
                       clockwise: false)
            path.addLine(to: CGPoint(x: width - br, y: height))
        } else {
            path.addLine(to: CGPoint(x: width, y: height))
        }
        
        // Don't draw bottom line or close the path
        // This eliminates the bottom border
        
        return path
    }
}
