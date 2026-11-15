import Foundation
import libxml2

enum MuseumText {
    static func expandingAbbreviations(in text: String) -> String {
        let replacements = [
            (#"(?:ca?|approx)\."#, "circa"),
            (#"no(s?)\."#, "number$1"),
            (#"fig(s?)\."#, "figure$1"),
            (#"vol(s?)\."#, "volume$1")
        ]
        return replacements.reduce(text) { result, replacement in
            let (abbreviation, expansion) = replacement
            return result.replacingOccurrences(
                of: #"(?i)(?<![\w.])\#(abbreviation)\s*(?=\d)"#,
                with: expansion + " ",
                options: .regularExpression
            )
        }
    }

    static func plain(_ source: String?) -> String? {
        guard let source, !source.isEmpty else { return nil }
        let wrapped = "<html><body>\(source)</body></html>"
        let options = HTML_PARSE_RECOVER.rawValue | HTML_PARSE_NOERROR.rawValue
            | HTML_PARSE_NOWARNING.rawValue | HTML_PARSE_NONET.rawValue
        let document = wrapped.withCString {
            htmlReadMemory($0, Int32(wrapped.utf8.count), nil, "UTF-8", Int32(options))
        }
        guard let document else { return nil }
        defer { xmlFreeDoc(document) }

        var text = ""
        append(xmlDocGetRootElement(document), to: &text)
        let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }

    private static func append(_ start: xmlNodePtr?, to output: inout String) {
        var cursor = start
        while let node = cursor {
            cursor = node.pointee.next
            if node.pointee.type == XML_TEXT_NODE, let content = node.pointee.content {
                output += String(cString: content)
            } else if node.pointee.type == XML_ELEMENT_NODE, let name = node.pointee.name {
                let tag = String(cString: name)
                guard !["head", "script", "style"].contains(tag) else { continue }
                let block = ["p", "li", "br", "div", "blockquote", "h1", "h2", "h3"].contains(tag)
                if block { output += " " }
                append(node.pointee.children, to: &output)
                if block { output += " " }
            }
        }
    }
}
