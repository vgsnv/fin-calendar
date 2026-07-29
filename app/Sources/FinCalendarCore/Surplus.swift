/// Свободные деньги (П6а, С12а): варианты применения излишка прихода.
/// Порядок предложений обратен порядку уступчивости П8:
/// согнутое последним возвращается первым — сначала даты платежей,
/// затем замыслы, затем фонды; после — ускорение статей; после — новое.
/// Последним всегда — «ничего не трогать»: излишек выходит из плана.

public enum BentDecision: Equatable, Sendable {
    case shiftedPaymentDate(name: String)
    case slowedIntent(name: String)
    case pausedIntent(name: String)
    case slowedFund(name: String)
    case pausedFund(name: String)

    /// Жёсткость согнутого: платёж согнут последним (П8) — возвращается первым.
    var returnPriority: Int {
        switch self {
        case .shiftedPaymentDate: return 0
        case .slowedIntent, .pausedIntent: return 1
        case .slowedFund, .pausedFund: return 2
        }
    }
}

public enum SurplusSuggestion: Equatable, Sendable {
    case returnBent(BentDecision)
    case accelerateArticle(name: String)
    case newPossibility            // новый замысел или повышение повседневных денег
    case leaveAlone                // излишек выйдет из плана и не вернётся (С12а)
}

public enum Surplus {
    /// Список предложений для излишка прихода. Ничего не применяется
    /// автоматически (П2); выбор и отказ равноценны.
    public static func suggestions(bent: [BentDecision],
                                   acceleratableArticles: [String]) -> [SurplusSuggestion] {
        var result: [SurplusSuggestion] = []
        for decision in bent.sorted(by: { $0.returnPriority < $1.returnPriority }) {
            result.append(.returnBent(decision))
        }
        for name in acceleratableArticles {
            result.append(.accelerateArticle(name: name))
        }
        result.append(.newPossibility)
        result.append(.leaveAlone)
        return result
    }
}
