import codecs
import unittest

from check_strings import ParseError
from check_strings import check_text
from check_strings import decode_strings


FINISHED_TEXT: str = """
"Chat.Service.PeerJoinedTelegram" = "%@ joined ImpulseM";
"Telegram.PeerInfoController" = "Info";
"ImpulseM.GeneralSettingsViewController" = "General Settings";
"ImpulseM.NotificationSettingsViewController" = "Notifications";
"ImpulseM.InstalledStickerPacksController" = "Stickers and Emoji";
"ImpulseM.LanguageViewController" = "Language";
"PremiumBoarding.Business.TelegramBusiness" = "ImpulseM Business";
"StorageUsage.TelegramUsage.Text" = "ImpulseM uses **%@** of your free disk space.";
"Business.Chatbots.Header" = "Read [More](https://impulsem.net/blog/telegram-business).";
"Chat.Context.Phone.NotTelegram" = "This number is not on ImpulseM";
"""

PRE_REBRAND_TEXT: str = """
"Telegram.GeneralSettingsViewController" = "General Settings";
"Telegram.NotificationSettingsViewController" = "Notifications";
"Telegram.InstalledStickerPacksController" = "Stickers and Emoji";
"Telegram.LanguageViewController" = "Language";
"Chat.Service.PeerJoinedTelegram" = "%@ joined Telegram";
"""


class CheckStringsTest(unittest.TestCase):

    def test_finished_text_passes(self) -> None:
        self.assertEqual(check_text(FINISHED_TEXT), [])

    def test_pre_rebrand_text_fails(self) -> None:
        failures: list[str] = check_text(PRE_REBRAND_TEXT)
        self.assertTrue(any("renamed key missing: ImpulseM.GeneralSettingsViewController" in failure for failure in failures))
        self.assertTrue(any("pre-rebrand key still present: Telegram.LanguageViewController" in failure for failure in failures))
        self.assertTrue(any("brand word left in value" in failure for failure in failures))

    def test_brand_word_in_value_fails(self) -> None:
        failures: list[str] = check_text(self.with_renamed_keys('"Chat.Title" = "Telegram Premium";'))
        self.assertEqual(len(failures), 1)
        self.assertIn("brand word left in value", failures[0])

    def test_compound_brand_word_fails(self) -> None:
        failures: list[str] = check_text(self.with_renamed_keys('"Chat.Title" = "Controleer je Telegramberichten";'))
        self.assertEqual(len(failures), 1)

    def test_upper_case_brand_word_fails(self) -> None:
        failures: list[str] = check_text(self.with_renamed_keys('"Chat.Invite" = "INVITE TO TELEGRAM";'))
        self.assertEqual(len(failures), 1)

    def test_escaped_brand_word_fails(self) -> None:
        failures: list[str] = check_text(self.with_renamed_keys(r'"Chat.Quote" = "Say \"Telegram\"";'))
        self.assertEqual(len(failures), 1)

    def test_allowed_literal_passes(self) -> None:
        self.assertEqual(check_text(self.with_renamed_keys('"Proxy.Name" = "TelegramWebviewProxy";')), [])

    def test_protected_forms_pass(self) -> None:
        text: str = self.with_renamed_keys(
            '"A" = "Open @Telegram";\n'
            '"B" = "Visit telegram.org";\n'
            '"C" = "Follow #Telegram";\n'
            '"D" = "{Telegram}";\n'
            '"E" = "Use Telegram.org guide";\n'
        )
        self.assertEqual(check_text(text), [])

    def test_upstream_link_host_fails(self) -> None:
        failures: list[str] = check_text(self.with_renamed_keys('"Invite.Link" = "Join t.me/abc";'))
        self.assertEqual(len(failures), 1)
        self.assertIn("upstream link host", failures[0])

    def test_comments_are_ignored(self) -> None:
        text: str = self.with_renamed_keys(
            '// "Chat.Old" = "Telegram Premium";\n'
            '/* "Chat.Older" = "Telegram"; */\n'
        )
        self.assertEqual(check_text(text), [])

    def test_brand_word_in_key_is_allowed(self) -> None:
        self.assertEqual(check_text(self.with_renamed_keys('"Telegram.PassportController" = "Passport";')), [])

    def test_utf16_le_with_bom_decodes(self) -> None:
        text: str = '"A" = "Value";\n'
        data: bytes = codecs.BOM_UTF16_LE + text.encode("utf-16-le")
        self.assertEqual(decode_strings(data), text)

    def test_utf16_le_with_brand_word_fails(self) -> None:
        text: str = self.with_renamed_keys('"Chat.Title" = "Telegram";\n')
        data: bytes = codecs.BOM_UTF16_LE + text.encode("utf-16-le")
        self.assertEqual(len(check_text(decode_strings(data))), 1)

    def test_unterminated_entry_raises(self) -> None:
        with self.assertRaises(ParseError):
            check_text('"A" = "x"')

    def test_quoted_punctuation_is_not_separator_raises(self) -> None:
        with self.assertRaises(ParseError):
            check_text('"A" = "x" ";"')

    def test_unterminated_string_raises(self) -> None:
        with self.assertRaises(ParseError):
            check_text('"A" = "x;\n')

    def with_renamed_keys(self, body: str) -> str:
        return (
            '"ImpulseM.GeneralSettingsViewController" = "General Settings";\n'
            '"ImpulseM.NotificationSettingsViewController" = "Notifications";\n'
            '"ImpulseM.InstalledStickerPacksController" = "Stickers and Emoji";\n'
            '"ImpulseM.LanguageViewController" = "Language";\n'
            + body
        )


if __name__ == "__main__":
    unittest.main()
