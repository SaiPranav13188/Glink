import Foundation

/// v1.5 tool-name rules, with the false-alarm fixes: whole words only, no vague verbs, read verbs skipped.
public enum ToolRules {
    public static let writeVerbs: Set<String> = ["delete","remove","drop","wipe","send","post","publish",
                                                 "pay","transfer","refund","update","write","create","insert","execute","deploy"]
    public static let readVerbs: Set<String> = ["get","list","read","find","search","fetch","show"]
    public static let piiWords: Set<String> = ["aadhaar","aadhar","pan","ifsc","cvv","upi","passport"]

    /// Splits `delete_order`, `deleteOrder` and `delete-order` into ["delete", "order"].
    public static func words(_ name: String) -> [String] {
        var out: [String] = [], cur = ""
        for ch in name {
            if ch.isLetter || ch.isNumber {
                if ch.isUppercase, let last = cur.last, last.isLowercase { out.append(cur.lowercased()); cur = "" }
                cur.append(ch)
            } else if !cur.isEmpty { out.append(cur.lowercased()); cur = "" }
        }
        if !cur.isEmpty { out.append(cur.lowercased()) }
        return out
    }

    public static func isWriteTool(_ name: String) -> Bool {
        let w = words(name)
        guard let first = w.first, !readVerbs.contains(first) else { return false }
        return w.contains(where: writeVerbs.contains)
    }
    public static func touchesPII(_ name: String) -> Bool { !Set(words(name)).isDisjoint(with: piiWords) }
}
