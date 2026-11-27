#!/usr/bin/env python3
import json
from pathlib import Path
import subprocess
import sys


def verify_export_localization(app: Path) -> None:
    executable = app / "Contents/MacOS/DictLocalAI"
    reports = {
        "en": (
            "Source: sample.wav\nProcessed: Partial, up to 00:00:00\n"
            "Timestamps start at the beginning of the session and come from speech recognition. Accuracy is about ±0.3 s.\n\n"
            "[00:00:00–00:00:02] Speaker 1: Тест Test"
        ),
        "ru": (
            "Источник: sample.wav\nОбработано: Частично, до 00:00:00\n"
            "Таймкоды: от начала сессии, по распознаванию речи, точность около ±0,3 с.\n\n"
            "[00:00:00–00:00:02] Спикер 1: Тест Test"
        ),
    }
    for preferences, expected in (
        ("(en)", "en"),
        ("(ru)", "ru"),
        ("(ru-RU, en)", "ru"),
        ("(en, ru)", "en"),
        ("(fr, ru)", "ru"),
        ("(fr)", "en"),
    ):
        response_json = subprocess.check_output(
            [executable, "--check-localization", "-AppleLanguages", preferences],
            text=True,
            timeout=30,
        )
        result = json.loads(response_json)
        expected_strings = {
            "en": ("Files", "00:01 of 00:02", ("Updated 1 segment", "Updated 2 segments",
                                               "Updated 5 segments"), "Record your voice",
                   "Capture system audio"),
            "ru": ("Файлы", "00:01 из 00:02", ("Исправлена 1 реплика", "Исправлены 2 реплики",
                                             "Исправлено 5 реплик"), "Запись вашей речи",
                   "Захват звука других приложений"),
        }
        title, progress, plurals, microphone, system_audio = expected_strings[expected]
        if not (
            {"en", "ru"} <= set(result["available"].split(","))
            and result["development"] == "en"
            and result["preferred"] == expected
            and result["export"] == reports[expected]
            and result["dictationTitle"] == ("Dictation" if expected == "en" else "Диктовка")
            and result["meetingTitle"] == ("Meeting 10:30" if expected == "en" else "Встреча 10:30")
            and result["files"] == title
            and result["progress"] == progress
            and all(result[key].startswith(value) for key, value in zip(("one", "few", "many"), plurals))
            and result["microphone"].startswith(microphone)
            and result["systemAudio"].startswith(system_audio)
        ):
            raise SystemExit(f"Unexpected localization for {preferences}: {result!r}")
        print(f"Verified localization for {preferences}: {expected}")


if __name__ == "__main__":
    verify_export_localization(Path(sys.argv[1]))
