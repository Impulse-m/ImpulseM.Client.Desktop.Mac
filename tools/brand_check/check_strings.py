import codecs
import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Token:
    kind: str
    text: str
    line: int


@dataclass(frozen=True)
class Entry:
    line: int
    key: str
    value: str


class ParseError(Exception):
    pass


RENAMED_KEY_SUFFIXES: tuple[str, ...] = (
    "GeneralSettingsViewController",
    "NotificationSettingsViewController",
    "InstalledStickerPacksController",
    "LanguageViewController",
)

# Literal spellings of the upstream name that are protocol or platform identifiers, not product text.
ALLOWED_LITERALS: tuple[str, ...] = (
    "TelegramWebviewProxy",
    "TelegramWebProxy",
    "window.Telegram.WebView.receiveEvent",
    " Telegram-Android/",
)

NATIVE_SPELLINGS: tuple[str, ...] = (
    "\u062a\u064a\u0644\u064a\u062c\u0631\u0627\u0645",
    "\u062a\u0644\u064a\u062c\u0631\u0627\u0645",
    "\ud154\ub808\uadf8\ub7a8",
)

PROTECTED_PARTS: tuple[str, ...] = (
    r"(?i:\{telegram\})",
    r"(?i:\]\(telegram\))",
    r"(?i:telegramdesktop)",
    r"TelegramTips\w*",
    r"[A-Za-z][A-Za-z0-9+.\-]*://[^\s\"'<>)]*",
    r"(?i:(?<![\w.])(?:t\.me|telegram\.me|telegram\.dog)/[^\s\"'<>)]*)",
    r"(?<!\w)www\.[^\s\"'<>)]*",
    r"@[\w.]+",
    r"#\w+",
)

WORD_START: str = r"(?<![@/=])(?<![^\W_])(?<![^\W_]_)"

BRAND_WORD_PATTERN: str = WORD_START + r"Telegram(?!\.(?:org|me|dog)\b)"
BRAND_UPPER_PATTERN: str = WORD_START + r"TELEGRAM\b(?!\.[^\W\d_])"
BRAND_NATIVE_PATTERN: str = "|".join(re.escape(spelling) for spelling in NATIVE_SPELLINGS)

BRAND_LEFTOVER_PATTERN: re.Pattern[str] = re.compile(
    "("
    + "|".join(PROTECTED_PARTS)
    + ")|("
    + BRAND_WORD_PATTERN
    + ")|("
    + BRAND_UPPER_PATTERN
    + ")|("
    + BRAND_NATIVE_PATTERN
    + ")"
)

BARE_LINK_HOST_PATTERN: re.Pattern[str] = re.compile(
    r"(?i:(?<![\w.\-])(?:t\.me|telegram\.me|telegram\.dog)(?![\w\-]))"
)


def decode_strings(data: bytes) -> str:
    if data.startswith(codecs.BOM_UTF16_LE) or data.startswith(codecs.BOM_UTF16_BE):
        return data.decode("utf-16")
    if data.startswith(codecs.BOM_UTF8):
        return data.decode("utf-8-sig")
    return data.decode("utf-8")


def read_quoted(
    text: str,
    start: int,
    line: int
) -> tuple[str, int]:
    buffer: list[str] = []
    position: int = start + 1
    length: int = len(text)
    simple_escapes: dict[str, str] = {"n": "\n", "t": "\t", "r": "\r"}
    while position < length:
        character: str = text[position]
        if character == '"':
            return "".join(buffer), position + 1
        if character == "\\":
            if position + 1 >= length:
                break
            escaped: str = text[position + 1]
            if escaped in "Uu":
                digits: str = text[position + 2:position + 6]
                try:
                    buffer.append(chr(int(digits, 16)))
                    position += 6
                    continue
                except ValueError:
                    pass
            buffer.append(simple_escapes.get(escaped, escaped))
            position += 2
            continue
        buffer.append(character)
        position += 1
    raise ParseError("line " + str(line) + ": unterminated quoted string")


def tokenize(text: str) -> list[Token]:
    tokens: list[Token] = []
    position: int = 0
    line: int = 1
    length: int = len(text)
    while position < length:
        character: str = text[position]
        if character == "\n":
            line += 1
            position += 1
        elif character.isspace():
            position += 1
        elif text.startswith("//", position):
            end: int = text.find("\n", position)
            position = length if end == -1 else end
        elif text.startswith("/*", position):
            end = text.find("*/", position + 2)
            if end == -1:
                raise ParseError("line " + str(line) + ": unterminated comment")
            line += text.count("\n", position, end)
            position = end + 2
        elif character == '"':
            value: str
            end_of_string: int
            value, end_of_string = read_quoted(text, position, line)
            tokens.append(Token("string", value, line))
            line += text.count("\n", position, end_of_string)
            position = end_of_string
        elif character in "=;":
            tokens.append(Token("punct", character, line))
            position += 1
        else:
            word_end: int = position
            while word_end < length and not text[word_end].isspace() and text[word_end] not in '=;"':
                word_end += 1
            tokens.append(Token("word", text[position:word_end], line))
            position = word_end
    return tokens


def parse_entries(text: str) -> list[Entry]:
    tokens: list[Token] = tokenize(text)
    entries: list[Entry] = []
    index: int = 0
    while index < len(tokens):
        if index + 4 > len(tokens):
            raise ParseError("line " + str(tokens[index].line) + ": incomplete entry")
        key_token: Token = tokens[index]
        equals_token: Token = tokens[index + 1]
        value_token: Token = tokens[index + 2]
        end_token: Token = tokens[index + 3]
        if key_token.kind == "punct" or value_token.kind == "punct":
            raise ParseError("line " + str(key_token.line) + ": malformed entry")
        if equals_token.kind != "punct" or equals_token.text != "=":
            raise ParseError("line " + str(key_token.line) + ": expected '=' and ';'")
        if end_token.kind != "punct" or end_token.text != ";":
            raise ParseError("line " + str(key_token.line) + ": expected '=' and ';'")
        entries.append(Entry(key_token.line, key_token.text, value_token.text))
        index += 4
    return entries


def find_brand_leftovers(value: str) -> list[str]:
    cleaned: str = value
    for literal in ALLOWED_LITERALS:
        cleaned = cleaned.replace(literal, " ")
    leftovers: list[str] = []
    for match in BRAND_LEFTOVER_PATTERN.finditer(cleaned):
        if match.group(1) is not None:
            continue
        leftovers.append(match.group(0))
    return leftovers


def check_text(text: str) -> list[str]:
    entries: list[Entry] = parse_entries(text)
    keys: set[str] = {entry.key for entry in entries}
    failures: list[str] = []
    for suffix in RENAMED_KEY_SUFFIXES:
        renamed_key: str = "ImpulseM." + suffix
        old_key: str = "Telegram." + suffix
        if renamed_key not in keys:
            failures.append("renamed key missing: " + renamed_key)
        if old_key in keys:
            failures.append("pre-rebrand key still present: " + old_key)
    for entry in entries:
        for leftover in find_brand_leftovers(entry.value):
            failures.append(
                "line " + str(entry.line) + ": key " + ascii(entry.key)
                + ": brand word left in value: " + ascii(leftover)
            )
        if BARE_LINK_HOST_PATTERN.search(entry.value) is not None:
            failures.append(
                "line " + str(entry.line) + ": key " + ascii(entry.key)
                + ": upstream link host used in value"
            )
    return failures


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        sys.stderr.write("usage: check_strings.py <Localizable.strings>\n")
        return 2
    path: Path = Path(argv[1])
    try:
        data: bytes = path.read_bytes()
    except OSError as error:
        sys.stderr.write("cannot read " + str(path) + ": " + str(error) + "\n")
        return 2
    try:
        failures: list[str] = check_text(decode_strings(data))
    except (ParseError, ValueError) as error:
        sys.stderr.write(str(path) + ": " + str(error) + "\n")
        return 1
    if failures:
        for failure in failures:
            sys.stdout.write(str(path) + ": " + failure + "\n")
        sys.stdout.write("brand check failed: " + str(len(failures)) + " problem(s)\n")
        return 1
    sys.stdout.write("brand check passed: " + str(path) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
