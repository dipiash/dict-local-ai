import json
import plistlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "Resources/App"
LANGUAGES = ("en", "ru")
ENTRY = re.compile(r'("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*");')
SPECIFIER = re.compile(r"%(?:(\d+)\$)?(@|lld|%)")


def load_strings(path):
    result = {}
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        match = ENTRY.fullmatch(line)
        if match is None:
            raise ValueError(f"Invalid entry in {path}: {line}")
        key, value = map(json.loads, match.groups())
        if key in result or not value.strip():
            raise ValueError(f"Duplicate key or empty translation in {path}: {key}")
        result[key] = value
    return result


def format_arguments(value):
    result = []
    for position, specifier in SPECIFIER.findall(value):
        if specifier != "%":
            result.append((int(position) if position else len(result) + 1, specifier))
    if "%" in SPECIFIER.sub("", value):
        raise ValueError(f"Invalid format specifier: {value}")
    return sorted(result)


class LocalizationTests(unittest.TestCase):
    def test_ui_keys_and_format_arguments_match(self):
        en, ru = (load_strings(APP / f"{lang}.lproj/Localizable.strings") for lang in LANGUAGES)
        self.assertEqual(en.keys(), ru.keys())
        for key, value in en.items():
            with self.subTest(key=key):
                self.assertEqual(format_arguments(value), format_arguments(ru[key]))
        self.assertEqual((en["menu.files-label"], ru["menu.files-label"]), ("Files", "Файлы"))
        self.assertEqual(
            format_arguments(en["dictation.editor-instructions"]), [(1, "@"), (2, "@")]
        )

    def test_plural_keys_and_argument_types_match(self):
        catalogs = {
            lang: plistlib.loads((APP / f"{lang}.lproj/Localizable.stringsdict").read_bytes())
            for lang in LANGUAGES
        }
        self.assertEqual(catalogs["en"].keys(), catalogs["ru"].keys())
        for lang, catalog in catalogs.items():
            literals = load_strings(APP / f"{lang}.lproj/Localizable.strings")
            for key, entry in catalog.items():
                with self.subTest(lang=lang, key=key):
                    self.assertNotIn(key, literals)
                    self.assertEqual(entry["NSStringLocalizedFormatKey"], "%#@count@")
                    forms = entry["count"]
                    self.assertEqual(forms["NSStringFormatSpecTypeKey"], "NSStringPluralRuleType")
                    self.assertEqual(forms["NSStringFormatValueTypeKey"], "lld")
                    required = ("one", "other") if lang == "en" else ("one", "few", "many", "other")
                    for form in required:
                        self.assertEqual(format_arguments(forms[form]), [(1, "lld")])

    def test_all_literal_calls_have_translations(self):
        keys = load_strings(APP / "en.lproj/Localizable.strings").keys()
        plural = plistlib.loads((APP / "en.lproj/Localizable.stringsdict").read_bytes())
        sources = ROOT / "Sources/DictLocalAI"
        used = set()
        for source in sources.rglob("*.swift"):
            text = source.read_text()
            used.update(re.findall(r'(?:L10n\.text|AppFailure|\btext)\(\s*"([^"]+)"', text))
        self.assertEqual(set(), used - keys - plural.keys())

    def test_english_is_the_bundle_default_and_permission_keys_are_translated(self):
        info = plistlib.loads((APP / "Info.plist").read_bytes())
        self.assertEqual(info["CFBundleDevelopmentRegion"], "en")
        en, ru = (load_strings(APP / f"{lang}.lproj/InfoPlist.strings") for lang in LANGUAGES)
        self.assertEqual(en.keys(), ru.keys())
        for permission in ("NSMicrophoneUsageDescription", "NSAudioCaptureUsageDescription"):
            self.assertEqual(info[permission], en[permission])
            self.assertNotEqual(en[permission], ru[permission])
        self.assertNotIn("NSScreenCaptureUsageDescription", info)


    def test_app_presentation_has_no_russian_literals_outside_resources(self):
        sources = ROOT / "Sources/DictLocalAI"
        for source in sources.rglob("*.swift"):
            if source == sources / "Shared/Localization/LocalizationCheck.swift":
                continue
            with self.subTest(source=source.relative_to(ROOT)):
                self.assertNotRegex(source.read_text(), r"[А-Яа-яЁё]")
