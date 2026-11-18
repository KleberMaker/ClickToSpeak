import Foundation

// The release script runs this against the exact edit logic compiled into the app.
func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: UInt = #line) {
    if !condition() { fatalError("Ligne \(line) · \(message)") }
}

func edit(_ model: inout DictatedText, value: inout String, next: String) {
    if let (range, replacement) = model.replacement(for: next) {
        expect(range.location >= model.prefix.utf16.count, "Écriture avant la dictée")
        expect(NSMaxRange(range) <= model.prefix.utf16.count + model.spoken.utf16.count, "Écriture après la dictée")
        value = (value as NSString).replacingCharacters(in: range, with: replacement)
    }
    model.accept(next)
    expect(model.matches(value, model.selection), "Le contenu attendu diverge")
}

var empty = try DictatedText(original: "", selection: NSRange(location: 0, length: 0))
var value = ""
for word in ["Bon", "Bonjour", "Bonjour !", "Bonjour !", "", "Salut."] { edit(&empty, value: &value, next: word) }
expect(value == "Salut.", "Révision dans un champ vide")

value = "👩🏽‍💻 avant | après"
let selection = (value as NSString).range(of: "avant ")
var middle = try DictatedText(original: value, selection: selection)
expect(middle.selection == selection, "La préparation doit préserver la sélection")
for text in ["é", "e\u{301}cole", "écolier", "écolière 🧑‍🎓"] { edit(&middle, value: &value, next: text) }
expect(value == "👩🏽‍💻 avant écolière 🧑‍🎓| après", "Sélection ou suffixe écrasé")
expect(!middle.matches(value + ".", middle.selection), "Modification manuelle ignorée")
expect(!middle.matches(value, NSRange(location: 0, length: 0)), "Déplacement du curseur ignoré")
expect(middle.replacement(for: middle.spoken) == nil, "Écriture superflue")
let revision = middle.replacement(for: "écolière 👩‍🎓")!
expect(revision.0.location == "👩🏽‍💻 avant écolière ".utf16.count, "Préfixe dicté stable réécrit")
expect(revision.0.length == "🧑‍🎓".utf16.count, "Mauvaise longueur UTF-16")

var transcript = Transcript()
transcript.receive("Je", end: 0.2, final: false)
transcript.receive("Je dicte", end: 1.0, final: false)
expect(transcript.text == "Je dicte", "Provisoire dupliqué")
transcript.receive("Je dicte", end: 1.0, final: true)
transcript.receive("Je dicte", end: 1.0, final: true)
transcript.receive("Je", end: 0.2, final: false)
transcript.receive("en", end: 1.4, final: false)
transcript.receive(" en français.", end: 2.0, final: true)
expect(transcript.text == "Je dicte en français.", "Jonction ou final en double")
expect(transcript.provisional.isEmpty, "Hypothèse provisoire après finalisation")
do {
    _ = try DictatedText(original: "🦊", selection: NSRange(location: 1, length: 0))
    fatalError("Un curseur au milieu d’un surrogate a été accepté")
} catch is DictationError {}
print("Tests du texte dicté réussis.")
