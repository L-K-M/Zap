/// A direction for moving the highlight through the revealed window list/grid with
/// the arrow keys. Left/right only do anything in the multi-column preview grid; in
/// the single-column list they're no-ops, and up/down behave as before.
enum WindowNavDirection: Equatable {
    case up, down, left, right
}
