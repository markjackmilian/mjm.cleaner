/// Dove si trova davvero la root dichiarata da una regola. Il passo 3 confronta i percorsi come li
/// cancellerà il motore, che prima di eliminare risolve la root con `validateRoot`: senza la
/// risoluzione, una voce sotto `~/.cache` diretta altrove sfuggirebbe alla cartella che la contiene
/// (spec `2026-10-20-confirmation-containment-design.md`).
public protocol RootResolving: Sendable {
    func resolvedRoot(_ declaredRoot: String) -> String
}

extension PathGuard: RootResolving {
    /// La root canonica di `validateRoot`, con i collegamenti degli antenati risolti, anche quando
    /// la root è negata: le voci sotto una root negata non si cancellano comunque, e il percorso
    /// risolto riconosce più contenimenti, che è la direzione sicura. Senza un percorso canonico,
    /// la root dichiarata.
    public func resolvedRoot(_ declaredRoot: String) -> String {
        let canonical = validateRoot(declaredRoot).canonicalPathValidated
        return canonical.isEmpty ? declaredRoot : canonical
    }
}
