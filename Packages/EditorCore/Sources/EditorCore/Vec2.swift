// What: A 2D vector in normalized (0...1) image coordinates.
// Inputs/Outputs: Float x/y components; arithmetic and distance helpers return Vec2/Float.
// Threading: Value type, Sendable; safe on any thread.
import Foundation

/// A 2D vector in normalized image coordinates (0...1 in each axis).
public struct Vec2: Hashable, Codable, Sendable {
    public var x: Float
    public var y: Float

    public init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public var length: Float {
        (x * x + y * y).squareRoot()
    }

    public var lengthSquared: Float {
        x * x + y * y
    }

    public func distance(to other: Vec2) -> Float {
        (self - other).length
    }

    public static func + (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(lhs.x + rhs.x, lhs.y + rhs.y)
    }

    public static func - (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    public static func * (lhs: Vec2, rhs: Float) -> Vec2 {
        Vec2(lhs.x * rhs, lhs.y * rhs)
    }

    public static func * (lhs: Float, rhs: Vec2) -> Vec2 {
        Vec2(lhs * rhs.x, lhs * rhs.y)
    }

    public static func / (lhs: Vec2, rhs: Float) -> Vec2 {
        guard rhs != 0 else { return lhs }
        return Vec2(lhs.x / rhs, lhs.y / rhs)
    }

    public static prefix func - (value: Vec2) -> Vec2 {
        Vec2(-value.x, -value.y)
    }
}
