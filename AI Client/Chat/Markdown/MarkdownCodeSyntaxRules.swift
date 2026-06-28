struct ChatCodeSyntaxRules {
    let language: String
    let keywords: Set<String>
    let builtins: Set<String>
    let lineCommentMarkers: [String]
    let supportsBlockComments: Bool
    let supportsTripleQuotedStrings: Bool
    let supportsBacktickStrings: Bool
    let supportsPreprocessorDirectives: Bool

    init(language: String?) {
        let normalized = Self.normalized(language)
        self.language = normalized
        keywords = Self.keywords(for: normalized)
        builtins = Self.builtins(for: normalized)
        lineCommentMarkers = Self.lineCommentMarkers(for: normalized)
        supportsBlockComments = Self.blockCommentLanguages.contains(normalized)
        supportsTripleQuotedStrings = Self.tripleQuotedStringLanguages.contains(normalized)
        supportsBacktickStrings = Self.backtickStringLanguages.contains(normalized)
        supportsPreprocessorDirectives = Self.preprocessorLanguages.contains(normalized)
    }

    static let literalKeywords: Set<String> = [
        "true", "false", "nil", "null", "none", "None", "True", "False", "undefined", "nullptr"
    ]

    private static func normalized(_ language: String?) -> String {
        let token = language?.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .first.map(String.init) ?? ""
        switch token {
        case "c++", "cpp", "cc", "cxx", "hpp", "hxx": return "cpp"
        case "js", "jsx", "mjs", "cjs": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "rb": return "ruby"
        case "sh", "bash", "zsh": return "shell"
        case "yml": return "yaml"
        case "cs", "csharp": return "csharp"
        default: return token
        }
    }

    private static func lineCommentMarkers(for language: String) -> [String] {
        switch language {
        case "python", "ruby", "shell", "yaml", "toml", "makefile": return ["#"]
        case "sql": return ["--"]
        case "css", "json", "html", "xml": return []
        default: return ["//"]
        }
    }

    private static func keywords(for language: String) -> Set<String> {
        switch language {
        case "swift": return swiftKeywords
        case "python": return pythonKeywords
        case "javascript": return javaScriptKeywords
        case "typescript": return typeScriptKeywords
        case "c": return cKeywords
        case "cpp": return cppKeywords
        case "java": return javaKeywords
        case "kotlin": return kotlinKeywords
        case "csharp": return csharpKeywords
        case "go": return goKeywords
        case "rust": return rustKeywords
        case "shell": return shellKeywords
        case "sql": return sqlKeywords
        case "json": return []
        default: return sharedKeywords
        }
    }

    private static func builtins(for language: String) -> Set<String> {
        switch language {
        case "swift": return ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional"]
        case "python": return ["print", "range", "len", "list", "dict", "set", "tuple", "str", "int", "float", "bool", "self", "cls"]
        case "javascript", "typescript": return ["console", "Promise", "Array", "Object", "String", "Number", "Boolean", "Map", "Set", "JSON"]
        case "c": return ["printf", "scanf", "size_t", "NULL", "FILE"]
        case "cpp": return ["std", "vector", "string", "cout", "cin", "cerr", "endl", "size_t", "pair", "map", "set", "queue", "stack"]
        case "java", "kotlin": return ["String", "Integer", "Long", "Double", "Float", "Boolean", "List", "Map", "Set", "System"]
        case "csharp": return ["string", "object", "decimal", "Console", "List", "Dictionary", "Task"]
        case "go": return ["string", "int", "int64", "float64", "bool", "error", "byte", "rune", "make", "new", "append", "len", "cap"]
        case "rust": return ["String", "Vec", "Option", "Result", "Some", "Ok", "Err", "println"]
        default: return []
        }
    }

    private static let blockCommentLanguages: Set<String> = [
        "swift", "javascript", "typescript", "java", "kotlin", "c", "cpp", "csharp", "go", "rust", "css", "sql"
    ]
    private static let tripleQuotedStringLanguages: Set<String> = ["python", "swift", "kotlin"]
    private static let backtickStringLanguages: Set<String> = ["javascript", "typescript", "shell", "go"]
    private static let preprocessorLanguages: Set<String> = ["c", "cpp", "csharp", "swift"]

    private static let sharedKeywords: Set<String> = [
        "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "default",
        "defer", "do", "else", "enum", "extension", "final", "for", "func", "function", "guard",
        "if", "import", "in", "let", "private", "public", "return", "static", "struct", "switch",
        "throw", "throws", "try", "var", "while"
    ]

    private static let swiftKeywords = sharedKeywords.union([
        "actor", "associatedtype", "convenience", "didSet", "dynamic", "get", "inout", "internal",
        "isolated", "mutating", "nonisolated", "open", "override", "protocol", "required", "self",
        "Self", "set", "some", "super", "typealias", "where", "willSet"
    ])
    private static let pythonKeywords = sharedKeywords.union([
        "and", "assert", "def", "del", "elif", "except", "finally", "from", "global", "is", "lambda",
        "nonlocal", "not", "or", "pass", "raise", "with", "yield"
    ])
    private static let javaScriptKeywords = sharedKeywords.union([
        "abstract", "any", "boolean", "constructor", "debugger", "declare", "export", "extends",
        "implements", "interface", "namespace", "new", "of", "readonly", "require", "string",
        "symbol", "this", "type", "typeof", "void"
    ])
    private static let typeScriptKeywords = javaScriptKeywords.union(["keyof", "module", "never", "unknown"])
    private static let cKeywords: Set<String> = [
        "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else",
        "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register",
        "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef",
        "union", "unsigned", "void", "volatile", "while"
    ]
    private static let cppKeywords = cKeywords.union([
        "alignas", "alignof", "and", "asm", "bool", "catch", "char8_t", "char16_t", "char32_t",
        "class", "concept", "constexpr", "consteval", "constinit", "const_cast", "decltype", "delete",
        "dynamic_cast", "explicit", "export", "friend", "mutable", "namespace", "new", "noexcept",
        "operator", "private", "protected", "public", "reinterpret_cast", "requires", "static_assert",
        "static_cast", "template", "this", "thread_local", "throw", "try", "typename", "using", "virtual"
    ])
    private static let javaKeywords = cKeywords.union([
        "abstract", "assert", "boolean", "byte", "extends", "finally", "implements", "import",
        "instanceof", "interface", "native", "new", "package", "private", "protected", "public",
        "strictfp", "super", "synchronized", "this", "throws", "transient"
    ])
    private static let kotlinKeywords = sharedKeywords.union([
        "actual", "by", "companion", "constructor", "crossinline", "data", "expect", "fun", "init",
        "inner", "interface", "is", "object", "operator", "out", "override", "sealed", "suspend",
        "this", "typealias", "val", "when", "where"
    ])
    private static let csharpKeywords = javaKeywords.union([
        "base", "decimal", "delegate", "event", "fixed", "foreach", "implicit", "internal", "is",
        "lock", "nameof", "object", "out", "params", "partial", "ref", "sealed", "stackalloc",
        "string", "uint", "ulong", "unchecked", "unsafe", "ushort", "using"
    ])
    private static let goKeywords: Set<String> = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
        "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range",
        "return", "select", "struct", "switch", "type", "var"
    ]
    private static let rustKeywords = sharedKeywords.union([
        "crate", "dyn", "extern", "fn", "impl", "loop", "match", "mod", "move", "mut", "pub",
        "ref", "Self", "self", "trait", "type", "unsafe", "use", "where"
    ])
    private static let shellKeywords: Set<String> = [
        "case", "do", "done", "elif", "else", "esac", "export", "fi", "for", "function", "if",
        "in", "local", "readonly", "return", "select", "shift", "then", "unset", "until", "while"
    ]
    private static let sqlKeywords: Set<String> = [
        "select", "from", "where", "join", "left", "right", "inner", "outer", "insert", "update",
        "delete", "create", "alter", "drop", "table", "view", "index", "group", "order", "by",
        "having", "limit", "offset", "values", "into", "set", "and", "or", "not", "null", "is"
    ]
}
