//
//  Int+DayOfMonth.swift
//  Finova
//
//  Created by Arthur Rios on 03/08/26.
//

import Foundation

extension Int {

    /// A day number formatted for the current language: "31st" in English, plain "31" elsewhere.
    ///
    /// Shared by the transaction face ("Balance on the 31st") and the allocations face
    /// ("By Aug 31") so the two can never disagree about the day they refer to.
    var localizedDayOfMonth: String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        guard language == "en" else { return String(self) }
        return withEnglishOrdinalSuffix
    }

    /// "1st", "2nd", "3rd", "4th"… English only.
    var withEnglishOrdinalSuffix: String {
        let suffix: String
        if self >= 11 && self <= 13 {
            suffix = "th"
        } else {
            switch self % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(self)\(suffix)"
    }
}
