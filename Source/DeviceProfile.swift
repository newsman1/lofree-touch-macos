import Foundation

// The verified descriptor is stronger evidence of this specific report layout
// than IOHIDDeviceConformsTo, which returned false on the user's actual mouse.
func matchesVerifiedProfile(vendor: Int?, product: Int?, transport: String, descriptor: Data?) -> Bool {
    vendor == 9354 && product == 33382 && transport.lowercased().contains("bluetooth") && descriptor == Data(verifiedDescriptor)
}
