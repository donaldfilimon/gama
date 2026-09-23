public import GamaAuthoring

/// One word of a console line. A quoted word is always text, never a
/// number or keyword, so `"2"` names an entity called 2.
public struct ConsoleWord: Hashable, Sendable {
    public var text: String
    public var quoted: Bool

    public init(_ text: String, quoted: Bool = false) {
        self.text = text
        self.quoted = quoted
    }

    /// The keyword this word spells, or `nil` when it was quoted.
    var keyword: String? { quoted ? nil : text.lowercased() }
}

/// Parses one console line into a ``ConsoleAction`` against the current
/// document and selection (ADR 0006).
///
/// Grammar: `verb [target] arguments…`. Words are case-insensitive, and
/// double quotes group words (`"Key Light"`). A target is `selected`, `all`
/// (for `select`), `#<id>`, or an entity name matched case-insensitively.
/// An omitted target means the current selection. A target is present
/// exactly when the first argument is not a number, so an entity whose name
/// is a number must be written as `#<id>` or quoted.
///
/// Parsing never edits anything: it only reads `document` and `selection`,
/// and every edit it returns still goes through ``EditorSession``, which
/// validates it and can refuse it.
public struct ConsoleParser: Sendable {
    public let document: SceneDocument
    public let selection: Selection

    public init(document: SceneDocument, selection: Selection) {
        self.document = document
        self.selection = selection
    }

    /// The verbs and their usage, in the order `help` lists them.
    public static let usage: [(verb: String, usage: String)] = [
        ("add", "add box|sphere|cylinder|cone|plane|camera | add light [directional|point|spot]"),
        ("select", "select <target>|all|none"),
        ("move", "move [target] <dx> <dy> <dz>   (relative, meters)"),
        ("position", "position [target] <x> <y> <z>"),
        ("scale", "scale [target] <s> | <sx> <sy> <sz>"),
        ("color", "color [target] <r> <g> <b> [a]   (linear, 0…1)"),
        ("metallic", "metallic [target] <0…1>"),
        ("roughness", "roughness [target] <0…1>"),
        ("intensity", "intensity [target] <value>   (lux or lumens)"),
        ("fov", "fov [target] <degrees>"),
        ("rename", "rename [target to] <name>"),
        ("parent", "parent [target] to <target>|none"),
        ("duplicate", "duplicate [target]"),
        ("delete", "delete [target]"),
        ("hide", "hide|show|lock|unlock [target]"),
        ("undo", "undo | redo"),
        ("help", "help [verb]"),
    ]

    /// Parses `line`. An empty or blank line is an error the caller can
    /// ignore; every other failure explains what was expected.
    public func parse(_ line: String) throws(ConsoleError) -> ConsoleAction {
        var words = try Self.tokenize(line)
        guard !words.isEmpty else { throw ConsoleError("empty command") }
        let verb = words.removeFirst().text.lowercased()
        switch verb {
        case "add": return try add(words)
        case "select": return try select(words)
        case "undo": try expectNone(words, verb); return .undo
        case "redo": try expectNone(words, verb); return .redo
        case "help", "?": return .help(Self.help(words.first?.text.lowercased()))
        case "move", "position": return try placement(verb, words)
        case "scale": return try scale(words)
        case "color", "colour": return try color(words)
        case "metallic", "roughness": return try materialScalar(verb, words)
        case "intensity": return try intensity(words)
        case "fov": return try fieldOfView(words)
        case "rename": return try rename(words)
        case "parent": return try parent(words)
        case "duplicate": return try perTarget("Duplicate", words) { DuplicateEntity($0) }
        case "delete", "remove": return try delete(words)
        case "hide", "show", "lock", "unlock": return try visibility(verb, words)
        default:
            throw ConsoleError("unknown command '\(verb)'; type 'help' for the list")
        }
    }

    // MARK: Verbs

    func add(_ words: [ConsoleWord]) throws(ConsoleError) -> ConsoleAction {
        guard let kind = words.first?.keyword else {
            throw ConsoleError("usage: \(Self.usageLine("add"))")
        }
        if let primitive = Primitive(rawValue: kind == "cube" ? "box" : kind) {
            try expectNone(Array(words.dropFirst()), "add \(kind)")
            return .addPrimitive(primitive)
        }
        switch kind {
        case "camera":
            try expectNone(Array(words.dropFirst()), "add camera")
            return .addCamera
        case "light":
            let rest = words.dropFirst().map { $0.text.lowercased() }
            switch rest.first {
            case nil, "point": break
            case "directional", "sun": if rest.count == 1 { return .addLight(.directional) }
            case "spot": if rest.count == 1 {
                // The same default cone the inspector's kind cycle uses.
                return .addLight(.spot(innerAngleDegrees: 30, outerAngleDegrees: 45, attenuationRadius: 10))
            }
            default: throw ConsoleError("unknown light kind '\(rest[0])'; use directional, point, or spot")
            }
            guard rest.count <= 1 else { throw ConsoleError("usage: \(Self.usageLine("add"))") }
            return .addLight(.point(attenuationRadius: 10))
        default:
            throw ConsoleError("cannot add '\(kind)'; use box, sphere, cylinder, cone, plane, light, or camera")
        }
    }

    func select(_ words: [ConsoleWord]) throws(ConsoleError) -> ConsoleAction {
        guard !words.isEmpty else { throw ConsoleError("usage: \(Self.usageLine("select"))") }
        switch words.count == 1 ? words[0].keyword : nil {
        case "none"?, "nothing"?: return .select([])
        case "all"?:
            return .select(document.roots.flatMap { document.subtree($0) })
        default:
            guard words.count == 1 else {
                throw ConsoleError("select takes one target; quote names with spaces")
            }
            return .select(try resolve(words[0]))
        }
    }

    func placement(_ verb: String, _ words: [ConsoleWord]) throws(ConsoleError) -> ConsoleAction {
        let (targets, numbers) = try split(words, verb: verb)
        guard numbers.count == 3 else { throw ConsoleError("usage: \(Self.usageLine(verb))") }
        let value = SIMD3(numbers[0], numbers[1], numbers[2])
        return edit(verb == "move" ? "Move" : "Position", targets) { id in
            var transform = currentTransform(id)
            transform.position = verb == "move" ? transform.position + value : value
            return SetComponent(id, .transform(transform))
        }
    }

    func scale(_ words: [ConsoleWord]) throws(ConsoleError) -> ConsoleAction {
        let (targets, numbers) = try split(words, verb: "scale")
        let value: SIMD3<Float>
        switch numbers.count {
        case 1: value = SIMD3(repeating: numbers[0])
        case 3: value = SIMD3(numbers[0], numbers[1], numbers[2])
        default: throw ConsoleError("usage: \(Self.usageLine("scale"))")
        }
        return edit("Scale", targets) { id in
            var transform = currentTransform(id)
            transform.scale = value
            return SetComponent(id, .transform(transform))
        }
    }

    func color(_ words: [ConsoleWord]) throws(ConsoleError) -> ConsoleAction {
        let (targets, numbers) = try split(words, verb: "color")
        guard numbers.count == 3 || numbers.count == 4 else {
            throw ConsoleError("usage: \(Self.usageLine("color"))")
        }
        return edit("Color", targets) { id in
            var material = currentMaterial(id)
            let alpha = numbers.count == 4 ? numbers[3] : material.baseColor.w
            material.baseColor = SIMD4(numbers[0], numbers[1], numbers[2], alpha)
            return SetComponent(id, .material(material))
        }
    }

    func materialScalar(_ verb: String, _ words: [ConsoleWord]) throws(ConsoleError) -> ConsoleAction {
        let (targets, numbers) = try split(words, verb: verb)
        guard numbers.count == 1 else { throw ConsoleError("usage: \(Self.usageLine(verb))") }
        return edit(verb == "metallic" ? "Metallic" : "Roughness", targets) { id in
            var material = currentMaterial(id)
            if verb == "metallic" { material.metallic = numbers[0] } else { material.roughness = numbers[0] }
            return SetComponent(id, .material(material))
        }
    }

    func intensity(_ words: [ConsoleWord]) throws(ConsoleError) -> ConsoleAction {
        let (targets, numbers) = try split(words, verb: "intensity")
        guard numbers.count == 1 else { throw ConsoleError("usage: \(Self.usageLine("intensity"))") }
        var commands: [any DocumentCommand] = []
        for id in targets {
            guard case .light(var light)? = document.component(.light, of: id) else {
                throw ConsoleError("\(describe(id)) has no light")
            }
            light.intensity = numbers[0]
            commands.append(SetComponent(id, .light(light)))
        }
        return .edit(label: Self.plural("Intensity", commands.count), commands: commands)
    }

    func fieldOfView(_ words: [ConsoleWord]) throws(ConsoleError) -> ConsoleAction {
        let (targets, numbers) = try split(words, verb: "fov")
        guard numbers.count == 1 else { throw ConsoleError("usage: \(Self.usageLine("fov"))") }
        var commands: [any DocumentCommand] = []
        for id in targets {
            guard case .camera(var camera)? = document.component(.camera, of: id) else {
                throw ConsoleError("\(describe(id)) has no camera")
            }
            camera.fieldOfViewDegrees = numbers[0]
            commands.append(SetComponent(id, .camera(camera)))
        }
        return .edit(label: Self.plural("Field of View", commands.count), commands: commands)
    }

    func rename(_ words: [ConsoleWord]) throws(ConsoleError) -> ConsoleAction {
        let targets: [EntityID]
        let nameWords: ArraySlice<ConsoleWord>
        if let to = words.firstIndex(where: { $0.keyword == "to" }), to == 1 {
            targets = try resolve(words[0])
            nameWords = words[2...]
        } else {
            targets = try selectionTargets()
            nameWords = words[...]
        }
        guard !nameWords.isEmpty else { throw ConsoleError("usage: \(Self.usageLine("rename"))") }
        let name = nameWords.map(\.text).joined(separator: " ")
        return edit("Rename", targets) { RenameEntity($0, to: name) }
    }

    func parent(_ words: [ConsoleWord]) throws(ConsoleError) -> ConsoleAction {
        guard let to = words.firstIndex(where: { $0.keyword == "to" }), to <= 1, to == words.count - 2 else {
            throw ConsoleError("usage: \(Self.usageLine("parent"))")
        }
        let targets = to == 1 ? try resolve(words[0]) : try selectionTargets()
        let destination = words[to + 1]
        let newParent: EntityID?
        if let keyword = destination.keyword, ["none", "root"].contains(keyword) {
            newParent = nil
        } else {
            let resolved = try resolve(destination)
            guard resolved.count == 1 else { throw ConsoleError("a parent must be one entity") }
            newParent = resolved[0]
        }
        return edit("Reparent", targets) { ReparentEntity($0, to: newParent) }
    }

    func delete(_ words: [ConsoleWord]) throws(ConsoleError) -> ConsoleAction {
        var targets = try targets(words, verb: "delete")
        // Deleting an ancestor deletes its subtree; a descendant listed too
        // would already be gone when its own command ran.
        targets = targets.filter { id in
            !targets.contains { other in other != id && document.isSelfOrAncestor(other, of: id) }
        }
        return edit("Delete", targets) { DeleteEntity($0) }
    }

    func visibility(_ verb: String, _ words: [ConsoleWord]) throws(ConsoleError) -> ConsoleAction {
        let targets = try targets(words, verb: verb)
        let label = verb.prefix(1).uppercased() + verb.dropFirst()
        return edit(label, targets) { id in
            var visibility = Visibility()
            if case .visibility(let current)? = document.component(.visibility, of: id) { visibility = current }
            switch verb {
            case "hide": visibility.visible = false
            case "show": visibility.visible = true
            case "lock": visibility.locked = true
            default: visibility.locked = false
            }
            return SetComponent(id, .visibility(visibility))
        }
    }

    func perTarget(
        _ label: String, _ words: [ConsoleWord], _ make: (EntityID) -> any DocumentCommand
    ) throws(ConsoleError) -> ConsoleAction {
        edit(label, try targets(words, verb: label.lowercased()), make)
    }

    // MARK: Targets and arguments

    /// A target-only verb: zero words means the selection, one word a target.
    func targets(_ words: [ConsoleWord], verb: String) throws(ConsoleError) -> [EntityID] {
        switch words.count {
        case 0: return try selectionTargets()
        case 1: return try resolve(words[0])
        default: throw ConsoleError("usage: \(Self.usageLine(verb)); quote names with spaces")
        }
    }

    /// Splits `[target] numbers…`: the target is present exactly when the
    /// first word is not a number.
    func split(_ words: [ConsoleWord], verb: String) throws(ConsoleError) -> ([EntityID], [Float]) {
        var rest = words[...]
        let targets: [EntityID]
        if let first = rest.first, first.quoted || Self.number(first.text) == nil {
            targets = try resolve(first)
            rest = rest.dropFirst()
        } else {
            targets = try selectionTargets()
        }
        var numbers: [Float] = []
        for word in rest {
            guard !word.quoted, let value = Self.number(word.text) else {
                throw ConsoleError("'\(word.text)' is not a number; usage: \(Self.usageLine(verb))")
            }
            numbers.append(value)
        }
        return (targets, numbers)
    }

    func selectionTargets() throws(ConsoleError) -> [EntityID] {
        guard !selection.isEmpty else {
            throw ConsoleError("nothing is selected; name a target or select one first")
        }
        return selection.ordered
    }

    /// `selected`, `#<id>`, or a case-insensitive exact entity name. A quoted
    /// word is always a name.
    public func resolve(_ target: ConsoleWord) throws(ConsoleError) -> [EntityID] {
        let word = target.text
        let lowered = word.lowercased()
        if target.keyword == "selected" || target.keyword == "selection" {
            return try selectionTargets()
        }
        if !target.quoted, word.hasPrefix("#") {
            guard let raw = UInt64(word.dropFirst()), document.contains(EntityID(rawValue: raw)) else {
                throw ConsoleError("no entity \(word)")
            }
            return [EntityID(rawValue: raw)]
        }
        let matches = document.entities.values
            .filter { $0.name.lowercased() == lowered }
            .map(\.id)
            .sorted()
        switch matches.count {
        case 0: throw ConsoleError("no entity named '\(word)'")
        case 1: return matches
        default:
            let listed = matches.map { describe($0) }.joined(separator: ", ")
            throw ConsoleError("'\(word)' is ambiguous (\(listed)); use #<id>")
        }
    }

    // MARK: Helpers

    func edit(
        _ verb: String, _ targets: [EntityID], _ make: (EntityID) -> any DocumentCommand
    ) -> ConsoleAction {
        let commands = targets.map(make)
        return .edit(label: Self.plural(verb, commands.count), commands: commands)
    }

    func currentTransform(_ id: EntityID) -> Transform {
        if case .transform(let transform)? = document.component(.transform, of: id) { return transform }
        return .identity
    }

    func currentMaterial(_ id: EntityID) -> Material {
        if case .material(let material)? = document.component(.material, of: id) { return material }
        return Material()
    }

    func describe(_ id: EntityID) -> String {
        "\(id) \(document.entity(id)?.name ?? "")"
    }

    func expectNone(_ words: [ConsoleWord], _ verb: String) throws(ConsoleError) {
        guard words.isEmpty else { throw ConsoleError("'\(verb)' takes no arguments") }
    }

    static func plural(_ verb: String, _ count: Int) -> String {
        count == 1 ? verb : "\(verb) \(count) Entities"
    }

    /// A finite decimal number, or `nil`. `inf` and `nan` are not numbers
    /// here: no component accepts them.
    static func number(_ word: String) -> Float? {
        guard let value = Float(word), value.isFinite,
              word.first.map({ $0.isNumber || $0 == "-" || $0 == "+" || $0 == "." }) == true
        else { return nil }
        return value
    }

    static func usageLine(_ verb: String) -> String {
        usage.first { $0.verb == verb }?.usage ?? verb
    }

    static func help(_ verb: String?) -> String {
        if let verb {
            guard let line = usage.first(where: { $0.verb == verb || $0.usage.hasPrefix("\(verb) ") || $0.usage.contains("|\(verb) ") }) else {
                return "unknown command '\(verb)'"
            }
            return line.usage
        }
        return "commands: " + usage.map(\.verb).joined(separator: ", ")
            + ". Target: selected, #id, or a name (quote names with spaces); omitted means the selection."
    }

    /// Splits on whitespace; double quotes group words, and `\"` escapes a
    /// quote inside them.
    public static func tokenize(_ line: String) throws(ConsoleError) -> [ConsoleWord] {
        var words: [ConsoleWord] = []
        var current = ""
        var inQuotes = false
        var quoted = false
        var escaped = false
        for character in line {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\", inQuotes {
                escaped = true
            } else if character == "\"" {
                inQuotes.toggle()
                quoted = true
            } else if character.isWhitespace, !inQuotes {
                if !current.isEmpty || quoted { words.append(ConsoleWord(current, quoted: quoted)) }
                current = ""
                quoted = false
            } else {
                current.append(character)
            }
        }
        guard !inQuotes else { throw ConsoleError("unterminated quote") }
        if !current.isEmpty || quoted { words.append(ConsoleWord(current, quoted: quoted)) }
        return words
    }
}
