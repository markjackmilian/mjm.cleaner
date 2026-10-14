/// Somme e differenze di byte che non vanno mai in trap. `Sum()` del C# lanciava
/// `OverflowException` e la pagina restava senza totale; in Swift `+` arresterebbe l'app. Le somme
/// saturano a `Int64.max`/`Int64.min`, un valore che resta comunque leggibile (registro di parità).
enum SafeSum {
    static func total<Values: Sequence>(_ values: Values) -> Int64 where Values.Element == Int64 {
        var sum: Int64 = 0
        for value in values {
            let (result, overflow) = sum.addingReportingOverflow(value)
            sum = overflow ? (value > 0 ? .max : .min) : result
        }
        return sum
    }

    /// `minuend - subtrahend`, saturata.
    static func difference(_ minuend: Int64, _ subtrahend: Int64) -> Int64 {
        let (result, overflow) = minuend.subtractingReportingOverflow(subtrahend)
        guard overflow else { return result }
        return subtrahend < 0 ? .max : .min
    }
}
