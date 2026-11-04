import Foundation

/// Deterministic natural-language parsing. It is the backbone for dates (NSDataDetector is exact about
/// calendars in a way a small language model isn't) and the full fallback when intelligence is unavailable.
enum HeuristicParser {
    struct Result {
        var draft: ReminderDraft
        var dateFound: Bool
    }

    static func parse(_ prompt: String, now: Date = .now) -> Result {
        var draft = ReminderDraft()
        draft.prompt = prompt
        draft.origin = .typed
        var working = " " + normalize(prompt.trimmingCharacters(in: .whitespacesAndNewlines)) + " "

        // 1. Repetition.
        if let (rule, range) = detectRepeat(in: working) {
            draft.repeatRule = rule
            // Keep weekday names ("every monday") for the date detector, drop the rest.
            let phrase = String(working[range])
            let weekday = weekdayName(in: phrase)
            working.replaceSubrange(range, with: weekday.map { " \($0) " } ?? " ")
        }

        // 2. Relative ("in 20 minutes").
        var dueDate: Date?
        if let (interval, range) = detectRelative(in: working) {
            dueDate = now.addingTimeInterval(interval).roundedToMinute
            draft.timeIsExplicit = true
            working.replaceSubrange(range, with: " ")
        }

        // 3. Absolute dates and times.
        if dueDate == nil, let detected = detectDate(in: working, now: now) {
            var date = detected.date
            let phrase = String(working[detected.range]).lowercased()
            draft.timeIsExplicit = detected.timeExplicit
            if !detected.timeExplicit {
                date = applyDayPart(phrase + " " + working.lowercased(), to: date, now: now)
            } else {
                date = fixMeridiem(date, phrase: phrase)
            }
            if date <= now, !detected.timeExplicit, Calendar.current.isDate(date, inSameDayAs: now),
               phrase.contains("tonight") || phrase.contains("evening"), Calendar.current.component(.hour, from: now) < 22 {
                date = QuickLater.nextHalfHour(after: now.addingTimeInterval(45 * 60))
            } else if date <= now, !phrase.contains("today") {
                date = draft.repeatRule.next(after: date) ?? Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
            }
            dueDate = date
            working.replaceSubrange(detected.range, with: " ")
        }

        // 4. Day of month ("on the 1st").
        if dueDate == nil, let (date, range) = detectDayOfMonth(in: working, now: now) {
            dueDate = date
            working.replaceSubrange(range, with: " ")
        }

        // 5. A bare time ("at 7", "at noon").
        if dueDate == nil, let (date, range) = detectBareTime(in: working, now: now) {
            dueDate = date
            draft.timeIsExplicit = true
            working.replaceSubrange(range, with: " ")
        }

        // 6. Bare day parts ("tonight", "this evening").
        if dueDate == nil, let (date, range) = detectDayPart(in: working, now: now) {
            dueDate = date
            working.replaceSubrange(range, with: " ")
        }

        // 7. A routine with no time ("every morning"): start at its next natural moment.
        if dueDate == nil, draft.repeatRule != .never {
            let lowered = prompt.lowercased()
            let hour = lowered.contains("evening") || lowered.contains("night") ? Prefs.eveningHour
                : lowered.contains("afternoon") ? 15 : Prefs.morningHour
            var date = at(hour: hour, minute: 0, after: now)
            if draft.repeatRule == .weekdays {
                while Calendar.current.isDateInWeekend(date) {
                    date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
                }
            }
            dueDate = date
        }

        draft.dueDate = dueDate

        // 8. More moments ("…and again at 12", "…and the day after as well").
        if let anchor = dueDate {
            draft.additionalDates = detectAdditional(in: &working, after: anchor, now: now)
        }
        if draft.dueDate == nil { draft.repeatRule = .never }
        draft.title = cleanTitle(working)
        draft.symbol = SymbolCatalog.guess(for: prompt)
        draft.tint = tint(for: draft.symbol)
        return Result(draft: draft, dateFound: dueDate != nil)
    }

    // MARK: Title

    static func cleanTitle(_ raw: String) -> String {
        var text = " " + raw.lowercased().replacingOccurrences(of: "\n", with: " ") + " "
        let leading = [
            "hey ", "please ", "can you ", "could you ", "remind me to ", "remind me ", "reminder to ", "reminder ",
            "don't forget to ", "dont forget to ", "don't let me forget to ", "i need to ", "i have to ", "i should ",
            "need to ", "have to ", "to ",
        ]
        let originalWords = raw.trimmingCharacters(in: .whitespaces)
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            for prefix in leading where trimmed.hasPrefix(prefix) {
                trimmed.removeFirst(prefix.count)
                changed = true
            }
        }
        text = " " + trimmed + " "
        for filler in [" and again ", " again ", " as well ", " too ", " also ", " tonight ", " this evening ", " this afternoon ", " this morning ", " in the morning ", " in the evening ", " in the afternoon "] {
            text = text.replacingOccurrences(of: filler, with: " ")
        }
        var words = text.split(separator: " ").map(String.init)
        let dangling: Set<String> = ["at", "on", "by", "in", "for", "every", "each", "and", "the", "around", "about", "from"]
        while let last = words.last, dangling.contains(last.trimmingCharacters(in: .punctuationCharacters)) { words.removeLast() }
        var result = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // Restore original casing word-for-word where possible (names, acronyms).
        let originals = originalWords.split(separator: " ").map(String.init)
        result = result.split(separator: " ").map { word in
            originals.first { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) == word.trimmingCharacters(in: .punctuationCharacters) }?
                .trimmingCharacters(in: .punctuationCharacters) ?? String(word)
        }.joined(separator: " ")
        return result.capitalizedFirst
    }

    // MARK: Repeat

    static func detectRepeat(in text: String) -> (RepeatRule, Range<String.Index>)? {
        let patterns: [(RepeatRule, String)] = [
            (.weekdays, #"\b(every|each|on)\s+weekdays?\b|\bweekdays\b"#),
            (.daily, #"\b(every|each)\s+(day|morning|night|evening|afternoon)\b|\bdaily\b"#),
            (.weekly, #"\b(every|each)\s+(week|monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|tues|wed|thu|thurs|fri|sat|sun)s?\b|\bweekly\b"#),
            (.monthly, #"\b(every|each)\s+month\b|\bmonthly\b"#),
            (.yearly, #"\b(every|each)\s+year\b|\b(yearly|annually)\b"#),
        ]
        for (rule, pattern) in patterns {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return (rule, range)
            }
        }
        return nil
    }

    private static func weekdayName(in phrase: String) -> String? {
        let names = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        let lowered = phrase.lowercased()
        if let full = names.first(where: { lowered.contains($0) }) { return full }
        return names.first { lowered.range(of: "\\b\($0.prefix(3))\\b", options: .regularExpression) != nil }
    }

    // MARK: Relative

    static func detectRelative(in text: String) -> (TimeInterval, Range<String.Index>)? {
        let pattern = #"\bin\s+(\d+(?:\.\d+)?|a|an|one|two|three|four|five|six|ten|fifteen|twenty|thirty|forty|forty-five|half an?)\s*(minutes?|mins?|hours?|hrs?|h|days?|weeks?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let full = Range(match.range, in: text),
              let amountRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }
        let words: [String: Double] = [
            "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "ten": 10,
            "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "forty-five": 45,
        ]
        let amountText = text[amountRange].lowercased()
        let amount = Double(amountText) ?? (amountText.hasPrefix("half") ? 0.5 : words[amountText] ?? 1)
        let seconds: Double
        switch text[unitRange].lowercased().first {
        case "h": seconds = 3600
        case "d": seconds = 86_400
        case "w": seconds = 604_800
        default: seconds = 60
        }
        return (amount * seconds, full)
    }

    // MARK: Absolute

    struct Detection {
        var date: Date
        var range: Range<String.Index>
        var timeExplicit: Bool
    }

    static func detectDate(in text: String, now: Date) -> Detection? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: nsRange) {
            guard let date = match.date, let range = Range(match.range, in: text) else { continue }
            let phrase = text[range].lowercased()
            let explicit = phrase.range(
                of: #"\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)|\d{1,2}:\d{2}|\bnoon\b|\bmidnight\b|o'?clock|\bat\s+\d"#,
                options: .regularExpression
            ) != nil
            return Detection(date: date, range: range, timeExplicit: explicit)
        }
        return nil
    }

    /// "at 6" almost always means 6 PM in a reminder; respect an explicit am/morning.
    static func fixMeridiem(_ date: Date, phrase: String) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let hasMarker = phrase.range(of: #"am\b|pm\b|a\.m\.|p\.m\.|morning|noon|midnight"#, options: .regularExpression) != nil
        guard !hasMarker, (1...7).contains(hour) else { return date }
        return calendar.date(byAdding: .hour, value: 12, to: date) ?? date
    }

    /// Applies "morning" / "evening" etc., or a sensible default time, to a date with no explicit time.
    static func applyDayPart(_ text: String, to date: Date, now: Date) -> Date {
        let calendar = Calendar.current
        var hour = Prefs.morningHour
        var minute = 0
        // Whichever day part is mentioned first wins ("morning and evening" starts in the morning).
        let parts: [(String, Int, Int)] = [
            ("morning", Prefs.morningHour, 0), ("afternoon", 15, 0), ("lunch", 12, 30),
            ("evening", Prefs.eveningHour, 0), ("tonight", Prefs.eveningHour, 0), ("night", Prefs.eveningHour, 0),
        ]
        let first = parts
            .compactMap { part -> (Int, Int, String.Index)? in
                text.range(of: part.0).map { (part.1, part.2, $0.lowerBound) }
            }
            .min { $0.2 < $1.2 }
        if let first {
            hour = first.0
            minute = first.1
        } else if calendar.isDate(date, inSameDayAs: now) {
            // "today" with no time: give it an hour.
            let next = now.addingTimeInterval(3600)
            hour = calendar.component(.hour, from: next)
            minute = calendar.component(.minute, from: next) < 30 ? 30 : 0
            if minute == 0 { hour += 1 }
        }
        let day = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: min(hour, 23), minute: minute, second: 0, of: day) ?? date
    }

    static func detectDayOfMonth(in text: String, now: Date) -> (Date, Range<String.Index>)? {
        let pattern = #"\b(?:on\s+)?the\s+(\d{1,2})(?:st|nd|rd|th)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let full = Range(match.range, in: text),
              let dayRange = Range(match.range(at: 1), in: text),
              let day = Int(text[dayRange]), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.day = day
        components.hour = Prefs.morningHour
        guard let date = Calendar.current.nextDate(after: now, matching: components, matchingPolicy: .nextTime) else { return nil }
        return (date, full)
    }

    // MARK: Multiple moments

    /// Common misspellings and shorthand, so the date detector sees real words.
    static func normalize(_ text: String) -> String {
        let fixes: [(String, String)] = [
            (#"\b(tomorrw|tomorow|tommorow|tommorrow|tomorroww|tmrw|tmr|tmrrw|2morrow)\b"#, "tomorrow"),
            (#"\b(tonite|2nite)\b"#, "tonight"),
            (#"\b(tday|2day)\b"#, "today"),
            (#"\b(mins)\b"#, "minutes"),
            (#"\b(hrs)\b"#, "hours"),
        ]
        var result = text
        for (pattern, replacement) in fixes {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        return result
    }

    /// Finds every further moment after the first, in reading order. Bare times ("again at 12") and
    /// day parts ("and in the evening") attach to the day of the moment before them; "the day after"
    /// repeats the previous moment a day later.
    static func detectAdditional(in text: inout String, after anchor: Date, now: Date) -> [Date] {
        let calendar = Calendar.current
        var extras: [Date] = []
        var last = anchor

        for _ in 0..<6 {
            var candidates: [(range: Range<String.Index>, date: Date)] = []

            if let range = text.range(
                of: #"\b(?:and\s+)?(?:also\s+)?(?:on\s+)?the\s+(?:day\s+after|next\s+day|following\s+day)\b(?!\s+tomorrow)"#,
                options: [.regularExpression, .caseInsensitive]
            ), let date = calendar.date(byAdding: .day, value: 1, to: last) {
                candidates.append((range, date))
            }

            if let detected = detectDate(in: text, now: now) {
                let phrase = String(text[detected.range]).lowercased()
                var date = detected.date
                if !hasDayWord(phrase) {
                    // "at 12" on its own belongs to the previous moment's day.
                    if let (time, _) = time(in: phrase, on: last) { date = time }
                } else if !detected.timeExplicit {
                    let hasPart = ["morning", "afternoon", "evening", "night", "lunch"].contains { phrase.contains($0) }
                    date = hasPart
                        ? applyDayPart(phrase, to: date, now: now)
                        : calendar.date(bySettingHour: calendar.component(.hour, from: last), minute: calendar.component(.minute, from: last), second: 0, of: date) ?? date
                } else {
                    date = fixMeridiem(date, phrase: phrase)
                }
                candidates.append((detected.range, date))
            }

            if let (date, range) = bareTime(in: text, on: last) {
                candidates.append((range, date))
            }

            if let range = text.range(of: #"\b(?:and\s+)?(?:again\s+)?(?:in\s+the\s+)?(morning|afternoon|evening|night)\b"#, options: [.regularExpression, .caseInsensitive]) {
                let part = text[range].lowercased()
                let hour = part.contains("morning") ? Prefs.morningHour : part.contains("afternoon") ? 15 : Prefs.eveningHour
                if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: last) {
                    candidates.append((range, date <= last ? calendar.date(byAdding: .day, value: 1, to: date) ?? date : date))
                }
            }

            guard let next = candidates.min(by: { $0.range.lowerBound < $1.range.lowerBound }) else { break }
            text.replaceSubrange(next.range, with: " ")
            let date = next.date.roundedToMinute
            if date > now, date != anchor.roundedToMinute, !extras.contains(date) {
                extras.append(date)
                last = date
            }
        }
        return extras.sorted()
    }

    private static func hasDayWord(_ phrase: String) -> Bool {
        phrase.range(
            of: #"today|tonight|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|\bmon\b|\btue|\bwed\b|\bthu|\bfri\b|\bsat\b|\bsun\b|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|\d+/\d+|\bnext\b|\bweek"#,
            options: .regularExpression
        ) != nil
    }

    /// "again at 12" → that time on `day`'s date, choosing AM/PM so it comes after `day`.
    private static func bareTime(in text: String, on day: Date) -> (Date, Range<String.Index>)? {
        guard let range = text.range(of: #"\b(?:and\s+)?(?:again\s+)?at\s+(?:\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.|p\.m\.)?|noon|midday|midnight)(?=\W|$)"#, options: [.regularExpression, .caseInsensitive]),
              let (date, _) = time(in: String(text[range]).lowercased(), on: day) else { return nil }
        return (date, range)
    }

    private static func time(in phrase: String, on day: Date) -> (Date, Bool)? {
        let calendar = Calendar.current
        if phrase.contains("noon") || phrase.contains("midday") {
            return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day).map { ($0, true) }
        }
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?"#),
              let match = regex.firstMatch(in: phrase, range: NSRange(phrase.startIndex..., in: phrase)),
              let hourRange = Range(match.range(at: 1), in: phrase),
              var hour = Int(phrase[hourRange]), (0...23).contains(hour) else { return nil }
        let minute = Range(match.range(at: 2), in: phrase).flatMap { Int(phrase[$0]) } ?? 0
        let marker = Range(match.range(at: 3), in: phrase).map { phrase[$0].lowercased() }
        if let marker {
            if marker.hasPrefix("p"), hour < 12 { hour += 12 }
            if marker.hasPrefix("a"), hour == 12 { hour = 0 }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day).map { ($0, true) }
        }
        let options = hour == 12 ? [12] : hour <= 7 ? [hour + 12, hour] : hour < 12 ? [hour, hour + 12] : [hour]
        for h in options {
            if let date = calendar.date(bySettingHour: h, minute: minute, second: 0, of: day), date > day { return (date, true) }
        }
        return calendar.date(bySettingHour: options[0], minute: minute, second: 0, of: day).map { ($0, true) }
    }

    static func detectBareTime(in text: String, now: Date) -> (Date, Range<String.Index>)? {
        let calendar = Calendar.current
        if let range = text.range(of: #"\b(?:at\s+)?(noon|midday|midnight)\b"#, options: [.regularExpression, .caseInsensitive]) {
            let hour = text[range].lowercased().contains("midnight") ? 0 : 12
            return (at(hour: hour, minute: 0, after: now), range)
        }
        let pattern = #"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?(?=\W|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let full = Range(match.range, in: text),
              let hourRange = Range(match.range(at: 1), in: text),
              var hour = Int(text[hourRange]), (0...23).contains(hour) else { return nil }
        let minute = Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 0
        let marker = Range(match.range(at: 3), in: text).map { text[$0].lowercased() }
        if let marker {
            if marker.hasPrefix("p"), hour < 12 { hour += 12 }
            if marker.hasPrefix("a"), hour == 12 { hour = 0 }
            return (at(hour: hour, minute: minute, after: now), full)
        }
        guard (1...12).contains(hour) else { return (at(hour: hour, minute: minute, after: now), full) }
        // No am/pm: take the next sensible occurrence. Small hours ("at 6") lean PM today.
        let pm = hour == 12 ? 12 : hour + 12
        let am = hour == 12 ? 12 : hour
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let slots: [(Date, Int)] = hour <= 7
            ? [(today, pm), (tomorrow, am), (tomorrow, pm)]
            : [(today, am), (today, pm), (tomorrow, am)]
        for (day, h) in slots {
            if let candidate = calendar.date(bySettingHour: h, minute: minute, second: 0, of: day), candidate > now {
                return (candidate, full)
            }
        }
        return (at(hour: hour, minute: minute, after: now), full)
    }

    private static func at(hour: Int, minute: Int, after now: Date) -> Date {
        let calendar = Calendar.current
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    static func detectDayPart(in text: String, now: Date) -> (Date, Range<String.Index>)? {
        let calendar = Calendar.current
        let parts: [(String, Int)] = [
            (#"\btonight\b|\bthis evening\b|\bin the evening\b"#, Prefs.eveningHour),
            (#"\bthis afternoon\b|\bin the afternoon\b"#, 15),
            (#"\bthis morning\b|\bin the morning\b"#, Prefs.morningHour),
        ]
        for (pattern, hour) in parts {
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            var date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
            if date <= now {
                // "Tonight" said after the evening hour still means tonight, while there's night left.
                if hour == Prefs.eveningHour, calendar.component(.hour, from: now) < 22 {
                    date = QuickLater.nextHalfHour(after: now.addingTimeInterval(45 * 60))
                } else {
                    date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
                }
            }
            return (date, range)
        }
        return nil
    }

    static func tint(for symbol: String) -> ReminderTint {
        switch symbol {
        case "phone", "message", "envelope", "person.2": .cobalt
        case "airplane", "drop", "bed.double": .ice
        case "cart", "fork.knife", "cup.and.saucer", "pawprint": .volt
        case "pills", "heart", "figure.run", "leaf", "house": .mint
        case "briefcase", "book", "graduationcap", "gift": .violet
        case "car", "trash", "creditcard": .steel
        default: .cobalt
        }
    }
}

enum QuickLater {
    /// Rounds up to the next :00 or :30.
    static func nextHalfHour(after date: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let add = minute == 0 || minute == 30 ? 0 : (minute < 30 ? 30 - minute : 60 - minute)
        return (calendar.date(byAdding: .minute, value: add, to: date) ?? date).roundedToMinute
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
