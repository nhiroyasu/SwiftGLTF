import Foundation
import simd
import SwiftGLTFCore
import SwiftGLTFParser

public struct RendererAnimationState {
    public var time: Float
    public var speed: Float
    public var isLooping: Bool

    public init(time: Float = 0, speed: Float = 1, isLooping: Bool = true) {
        self.time = time
        self.speed = speed
        self.isLooping = isLooping
    }
}

private func wrapTime(_ t: Float, duration: Float, looping: Bool) -> Float {
    guard duration > 0 else { return t }
    if looping {
        let m = fmodf(t, duration)
        return m < 0 ? m + duration : m
    } else {
        return max(0, min(duration, t))
    }
}

/// Find the keyframe interval containing the specified time `t` by binary search,
///
/// # Example
/// ```
/// times = [0, 1, 2], t = 1.25
/// ↓
/// (k0, k1, s) = (1, 2, 0.25)
/// ```
///
///
/// - Parameters:
///   - times: An array of keyframe times in ascending order (as per glTF specification).
///   - t: The time to sample (in seconds).
/// - Returns:` (k0, k1, s)`, where `k0` is the index of the previous keyframe, `k1` is the index of the next keyframe,
///           `s` is the normalized interpolation factor `[0, 1]` within the interval. At the edges, it returns `(0,0,0)` and `(last,last,0)`.
/// - Note: To avoid division by zero when the interval length is 0, we divide by a small value.
@inlinable @inline(__always)
func findKeyframeIndices(times: [Float], t: Float) -> (Int, Int, Float) {
    let count = times.count
    if count == 0 { return (0, 0, 0) }

    // Fast path checks without Optional overhead
    let first = times[0]
    if t <= first { return (0, 0, 0) }

    let lastIndex = count &- 1
    let last = times[lastIndex]
    if t >= last { return (lastIndex, lastIndex, 0) }

    // Binary search
    var lo = 0
    var hi = lastIndex
    while lo + 1 < hi {
        let mid = (lo + hi) >> 1
        if times[mid] <= t { lo = mid } else { hi = mid }
    }
    let t0 = times[lo]
    let t1 = times[hi]
    let dt = t1 - t0

    // Avoid division by zero while keeping branch predictable
    let s: Float = (dt <= 0) ? 0 : (t - t0) / dt
    return (lo, hi, s)
}

/// Optimized variant with a cursor hint.
/// - Parameter hint: last known lower-bound keyframe index (will be updated).
@inlinable @inline(__always)
func findKeyframeIndices(times: [Float], t: Float, hint: inout Int) -> (Int, Int, Float) {
    let count = times.count
    if count == 0 { return (0, 0, 0) }

    // Clamp hint to valid range [0, count-1]
    if hint < 0 { hint = 0 }
    if hint >= count { hint = count - 1 }

    // Move hint forward or backward to bracket t.
    while hint + 1 < count, t >= times[hint + 1] { hint &+= 1 }
    while hint > 0, t < times[hint] { hint &-= 1 }

    // Now hint is k0. Handle edges.
    if t <= times[0] { hint = 0; return (0, 0, 0) }
    if t >= times[count - 1] { hint = count - 1; return (hint, hint, 0) }

    let k0 = hint
    let k1 = k0 + 1
    let t0 = times[k0]
    let t1 = times[k1]
    let dt = t1 - t0
    let s: Float = (dt <= 0) ? 0 : (t - t0) / dt
    return (k0, k1, s)
}

private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

private func lerp3(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

private func lerpQuatNormalized(_ a: simd_quatf, _ b: simd_quatf, _ t: Float) -> simd_quatf {
    var qb = b
    if dot(a.vector, b.vector) < 0 { // avoid long path
        qb = simd_quatf(ix: -b.imag.x, iy: -b.imag.y, iz: -b.imag.z, r: -b.real)
    }
    let v = simd_mix(a.vector, qb.vector, SIMD4<Float>(repeating: t))
    let q = simd_quatf(vector: v)
    return simd_normalize(q)
}

private func cubicHermite(_ p0: Float, _ m0: Float, _ p1: Float, _ m1: Float, _ s: Float) -> Float {
    let s2 = s * s
    let s3 = s2 * s
    let h00 = 2*s3 - 3*s2 + 1
    let h10 = s3 - 2*s2 + s
    let h01 = -2*s3 + 3*s2
    let h11 = s3 - s2
    return h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1
}

struct AnimationTRS {
    var translation: SIMD3<Float>?
    var rotation: simd_quatf?
    var scale: SIMD3<Float>?

    func apply(_ matrix: float4x4) -> float4x4 {
        let matrixTRS = decomposeTRS(matrix)
        let t = self.translation ?? matrixTRS.translation
        let r = self.rotation ?? matrixTRS.rotation
        let s = self.scale ?? matrixTRS.scale
        return trs2matrix(t, r, s)
    }

    func apply(_ trs: TRS) -> TRS {
        var trs = trs
        trs.translation = self.translation ?? trs.translation
        trs.rotation = self.rotation ?? trs.rotation
        trs.scale = self.scale ?? trs.scale
        return trs
    }
}

/// Evaluate TRS channels of a resolved animation and return per-node overrides.
func evaluateTRS(
    type: GLTFAnimationType,
    interpolation: GLTFInterpolation,
    keyFrameTimes: [Float],
    duration: Float,
    time: Float,
    looping: Bool = true
) -> AnimationTRS {
    var trs = AnimationTRS()
    let t = wrapTime(time, duration: duration, looping: looping)

    // Only TRS
    switch type {
    case .translation, .rotation, .scale:
        break
    case .weights, .unknown:
        return trs
    }

    let (k0, k1, sFac) = findKeyframeIndices(times: keyFrameTimes, t: t)

    if k0 == k1 {
        // same as STEP
        let idx = k0
        switch type {
        case .translation(let values):
            trs.translation = values[idx]
        case .scale(let values):
            trs.scale = values[idx]
        case .rotation(let values):
            trs.rotation = simd_normalize(values[idx])
        case .weights, .unknown:
            break
        }
    }

    switch interpolation {
    case .step:
        let idx = k0
        switch type {
        case .translation(let values):
            trs.translation = values[idx]
        case .scale(let values):
            trs.scale = values[idx]
        case .rotation(let values):
            trs.rotation = simd_normalize(values[idx])
        case .weights, .unknown:
            break
        }

    case .linear:
        switch type {
        case .translation(let values):
            let a = values[k0]
            let b = values[k1]
            trs.translation = lerp3(a, b, sFac)
        case .scale(let values):
            let a = values[k0]
            let b = values[k1]
            trs.scale = lerp3(a, b, sFac)
        case .rotation(let values):
            let qa = values[k0]
            var qb = values[k1]
            // Ensure shortest path for slerp
            if dot(qa.vector, qb.vector) < 0 { qb = simd_quatf(vector: -qb.vector) }
            trs.rotation = simd_slerp(qa, qb, sFac)
        case .weights, .unknown:
            break
        }

    case .cubicSpline:
        let t0: Float = keyFrameTimes[k0]
        let t1: Float = keyFrameTimes[k1]
        let dt = max(1e-8, t1 - t0)
        switch type {
        case .translation(let values):
            let v0: simd_float3x3 = simd_float3x3(rows: [
                values[k0 * 3 + 0],
                values[k0 * 3 + 1],
                values[k0 * 3 + 2],
            ])
            let v1: simd_float3x3 = simd_float3x3(rows: [
                values[k1 * 3 + 0],
                values[k1 * 3 + 1],
                values[k1 * 3 + 2],
            ])
            let p0 = v0[1]
            let m0 = v0[2] * dt
            let p1 = v1[1]
            let m1 = v1[0] * dt
            let x = cubicHermite(p0.x, m0.x, p1.x, m1.x, sFac)
            let y = cubicHermite(p0.y, m0.y, p1.y, m1.y, sFac)
            let z = cubicHermite(p0.z, m0.z, p1.z, m1.z, sFac)
            trs.translation = SIMD3<Float>(x, y, z)

        case .scale(let values):
            let v0: simd_float3x3 = simd_float3x3(rows: [
                values[k0 * 3 + 0],
                values[k0 * 3 + 1],
                values[k0 * 3 + 2],
            ])
            let v1: simd_float3x3 = simd_float3x3(rows: [
                values[k1 * 3 + 0],
                values[k1 * 3 + 1],
                values[k1 * 3 + 2],
            ])
            let p0 = v0[1]
            let m0 = v0[2] * dt
            let p1 = v1[1]
            let m1 = v1[0] * dt
            let x = cubicHermite(p0.x, m0.x, p1.x, m1.x, sFac)
            let y = cubicHermite(p0.y, m0.y, p1.y, m1.y, sFac)
            let z = cubicHermite(p0.z, m0.z, p1.z, m1.z, sFac)
            trs.scale = SIMD3<Float>(x, y, z)

        case .rotation(let values):
            let v0: [simd_quatf] = [
                values[k0 * 4 + 0],
                values[k0 * 4 + 1],
                values[k0 * 4 + 2],
                values[k0 * 4 + 3],
            ]
            let v1: [simd_quatf] = [
                values[k1 * 4 + 0],
                values[k1 * 4 + 1],
                values[k1 * 4 + 2],
                values[k1 * 4 + 3],
            ]
            let p0 = v0[1]
            let m0 = v0[2] * dt
            let p1 = v1[1]
            let m1 = v1[0] * dt
            let x = cubicHermite(p0.vector.x, m0.vector.x, p1.vector.x, m1.vector.x, sFac)
            let y = cubicHermite(p0.vector.y, m0.vector.y, p1.vector.y, m1.vector.y, sFac)
            let z = cubicHermite(p0.vector.z, m0.vector.z, p1.vector.z, m1.vector.z, sFac)
            let w = cubicHermite(p0.vector.w, m0.vector.w, p1.vector.w, m1.vector.w, sFac)
            trs.rotation = simd_normalize(simd_quatf(ix: x, iy: y, iz: z, r: w))

        case .weights, .unknown:
            break
        }
    }

    return trs
}

func evaluateWeights(
    type: GLTFAnimationType,
    interpolation: GLTFInterpolation,
    keyFrameTimes: [Float],
    duration: Float,
    time: Float,
    looping: Bool = true
) -> [Float] {
    let t = wrapTime(time, duration: duration, looping: looping)

    guard case .weights(let values) = type else { return [] }
    if keyFrameTimes.isEmpty { return [] }

    let (k0, k1, sFac) = findKeyframeIndices(times: keyFrameTimes, t: t)

    switch interpolation {
    case .step:
        let width = values.count / max(1, keyFrameTimes.count)
        let base = k0 * width
        if base + width <= values.count {
            return Array(values[base..<(base + width)])
        } else {
            return []
        }

    case .linear:
        let width = values.count / max(1, keyFrameTimes.count)
        if k0 == k1 {
            let base = k0 * width
            if base + width <= values.count {
                return Array(values[base..<(base + width)])
            } else {
                return []
            }
        } else {
            let a0 = k0 * width
            let b0 = k1 * width
            if a0 + width <= values.count, b0 + width <= values.count {
                var w = Array(repeating: Float(0), count: width)
                for i in 0..<width { w[i] = lerp(values[a0 + i], values[b0 + i], sFac) }
                return w
            } else {
                return []
            }
        }

    case .cubicSpline:
        let width = (values.count / max(1, keyFrameTimes.count)) / 3
        if k0 == k1 {
            let base = k0 * (3 * width) + width
            if base + width <= values.count {
                return Array(values[base..<(base + width)])
            } else {
                return []
            }
        } else {
            let t0 = keyFrameTimes[k0]
            let t1 = keyFrameTimes[k1]
            let dt = max(1e-8, t1 - t0)
            let i0 = k0 * (3 * width)
            let i1 = k1 * (3 * width)
            var w = Array(repeating: Float(0), count: width)
            for i in 0..<width {
                let p0 = values[i0 + width + i]
                let m0 = values[i0 + 2 * width + i] * dt
                let p1 = values[i1 + width + i]
                let m1 = values[i1 + 0 + i] * dt
                w[i] = cubicHermite(p0, m0, p1, m1, sFac)
            }
            return w
        }
    }
}
