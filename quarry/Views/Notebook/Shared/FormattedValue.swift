import Foundation

extension Double {
    var abbreviatedString: String {
        if self >= 1_000_000 {
            return (self / 1_000_000).formatted(.number.precision(.fractionLength(1))) + "M"
        } else if self >= 10_000 {
            return (self / 1_000).formatted(.number.precision(.fractionLength(0))) + "K"
        } else if self >= 1_000 {
            return (self / 1_000).formatted(.number.precision(.fractionLength(1))) + "K"
        } else if self == self.rounded() {
            return Int(self).formatted(.number)
        } else {
            return self.formatted(.number.precision(.fractionLength(2)))
        }
    }
}
