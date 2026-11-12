// TexturePool — reuse intermediate textures across renders (never allocate per frame).
// What: pooled MTLTextures keyed by size/format/usage, with refcounting
// because render stages alias textures (stage 3 may point at stage 2's
// texture when geometry is neutral). Textures nobody references sit in
// the free list; purge() drops them (memory warnings, source changes).
// Inputs-outputs: descriptor in; pooled texture out (or nil on failure).
// Threading: used from the render thread only (single command buffer per frame).
import Foundation
import Metal

final class TexturePool {
    /// Manual Hashable: MTLTextureUsage does not conform to Hashable in
    /// this SDK, so hash/equals go through the raw values instead.
    private struct Key: Hashable {
        var width: Int
        var height: Int
        var pixelFormat: MTLPixelFormat
        var usage: MTLTextureUsage

        static func == (lhs: Key, rhs: Key) -> Bool {
            lhs.width == rhs.width && lhs.height == rhs.height
                && lhs.pixelFormat == rhs.pixelFormat && lhs.usage == rhs.usage
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(width)
            hasher.combine(height)
            hasher.combine(pixelFormat.rawValue)
            hasher.combine(usage.rawValue)
        }
    }

    private let device: MTLDevice
    private var free: [Key: [MTLTexture]] = [:]
    private var refCounts: [ObjectIdentifier: Int] = [:]
    private var keys: [ObjectIdentifier: Key] = [:]

    init(device: MTLDevice) {
        self.device = device
    }

    /// Returns a pooled texture for the descriptor, creating one when the
    /// free list is empty. The caller owns one reference (refcount 1).
    func acquire(width: Int, height: Int, pixelFormat: MTLPixelFormat, usage: MTLTextureUsage, label: String) -> MTLTexture? {
        let key = Key(width: width, height: height, pixelFormat: pixelFormat, usage: usage)
        if var list = free[key], let texture = list.popLast() {
            free[key] = list
            refCounts[ObjectIdentifier(texture)] = 1
            return texture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = usage
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = label
        refCounts[ObjectIdentifier(texture)] = 1
        keys[ObjectIdentifier(texture)] = key
        return texture
    }

    /// Adds one reference for an aliased texture (e.g. stage 3 pointing
    /// at stage 2's texture). No-op for textures this pool did not create.
    func retain(_ texture: MTLTexture?) {
        guard let texture else { return }
        let id = ObjectIdentifier(texture)
        guard refCounts[id] != nil else { return }
        refCounts[id, default: 0] += 1
    }

    /// Drops one reference. At zero the texture returns to the free list.
    /// No-op for nil, non-pool textures, or textures already at zero
    /// (double release is safe).
    func release(_ texture: MTLTexture?) {
        guard let texture else { return }
        let id = ObjectIdentifier(texture)
        guard var count = refCounts[id], count > 0 else { return }
        count -= 1
        refCounts[id] = count
        if count == 0, let key = keys[id] {
            free[key, default: []].append(texture)
        }
    }

    /// Drops every unreferenced texture. Checked-out textures are kept.
    /// Their bookkeeping is removed too, so a later texture allocated at
    /// a reused address cannot collide with a stale entry.
    func purge() {
        for list in free.values {
            for texture in list {
                let id = ObjectIdentifier(texture)
                refCounts.removeValue(forKey: id)
                keys.removeValue(forKey: id)
            }
        }
        free.removeAll()
    }

    /// Number of textures currently checked out (for the debug overlay).
    var checkedOutCount: Int {
        refCounts.values.filter { $0 > 0 }.count
    }
}
