import CoreGraphics

/// Turns a rubber-band pull into exactly one action per approach.
///
/// A pull past the top reports an offset below the trigger for many frames, and
/// prepending a page changes the content height while the finger may still be
/// down, which keeps the offset below the trigger. Firing on every update turns
/// one pull into a page-per-frame cascade, so the gate stays closed until the
/// list comes back above `reset`: only a real return to the top re-arms it.
///
/// The gap between `trigger` and `reset` is the hysteresis: a list that merely
/// sags a little after a load (still below `reset`) never re-opens the gate, and
/// no timer is involved.
struct OverscrollGate {
    /// Offsets are negative above the top of the content; pulling up is below this.
    let trigger: CGFloat
    /// The gate re-arms only once the list is back above this (closer to 0).
    let reset: CGFloat
    private(set) var isArmed = true
    /// How many times the gate has opened, for debug logs and tests.
    private(set) var firedCount = 0

    init(trigger: CGFloat = -55, reset: CGFloat = -10) {
        // A trigger that is not below the reset line would re-arm on the same
        // pull that fired it, which is the bug this type exists to prevent.
        precondition(trigger < reset && reset <= 0, "trigger must sit below reset")
        self.trigger = trigger
        self.reset = reset
    }

    /// Feeds one observed offset. Returns true only on the frame that should
    /// start a load; every other update returns false.
    mutating func update(offset: CGFloat) -> Bool {
        // Back inside the content: the next pull is a new approach.
        if offset > reset {
            isArmed = true
            return false
        }
        guard offset < trigger, isArmed else { return false }
        isArmed = false
        firedCount += 1
        return true
    }

    /// Re-arms without an offset change, for when the list itself is replaced
    /// (a jump) and the next pull should count as a new approach.
    mutating func rearm() {
        isArmed = true
    }
}
