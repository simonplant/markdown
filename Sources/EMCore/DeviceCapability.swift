/// Device capability for AI feature gating per [A-033].
/// Validated as part of SPIKE-005.
public enum DeviceCapability: Sendable {
    /// A16+ / M1+ — all AI features available.
    case fullAI
    /// Older devices — no generative AI.
    case noAI
}
