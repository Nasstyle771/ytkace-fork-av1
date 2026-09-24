import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class ThemeAndDisplayTests(unittest.TestCase):
    def test_makefile_includes_display_rate_hooks(self):
        makefile = (ROOT / "Makefile").read_text()
        self.assertIn("Tweak/Features/Appearance/DisplayRateHooks.mm", makefile)

    def test_preferences_declared_and_implemented(self):
        pref_h = (ROOT / "Tweak" / "Runtime" / "Preferences.h").read_text()
        pref_mm = (ROOT / "Tweak" / "Runtime" / "Preferences.mm").read_text()

        keys = [
            "YTKACEThemePresetKey",
            "YTKACEThemeCustomBgKey",
            "YTKACEThemeCustomSurfaceKey",
            "YTKACEAccentPresetKey",
            "YTKACEAccentCustomHexKey",
            "YTKACE120HzEnabledKey",
            "YTKACE120HzModeKey",
            "YTKACESmoothScrollBoostKey",
            "YTKACEPreserveVideoFPSKey",
            "YTKACEPreferredCodecKey",
            "YTKACEHighBitrateBufferBoostKey",
        ]
        for key in keys:
            self.assertIn(key, pref_h, f"Missing {key} in Preferences.h")
            self.assertIn(key, pref_mm, f"Missing {key} in Preferences.mm")

    def test_localizable_strings_contain_new_features(self):
        strings = (ROOT / "Resources" / "YTKACE.bundle" / "en.lproj" / "Localizable.strings").read_text()
        required_labels = [
            "Appearance & Themes",
            "Display & 120Hz",
            "THEME PRESETS",
            "Pure OLED Black",
            "Midnight Navy",
            "Crimson Ember",
            "Cyberpunk Neon",
            "PROMOTION ENGINE",
            "Enable ProMotion 120Hz",
            "Smooth Feed Scroll Boost",
            "Preserve Video Frame Rate",
            "Preferred Video Codec",
            "AV1 (High Efficiency)",
            "High-Bitrate Buffer Boost",
        ]
        for label in required_labels:
            self.assertIn(f'"{label}"', strings, f"Missing label {label} in Localizable.strings")

    def test_settings_pages_include_new_controllers(self):
        pages_h = (ROOT / "Tweak" / "Settings" / "YTKACESettingsPages.h").read_text()
        pages_mm = (ROOT / "Tweak" / "Settings" / "YTKACESettingsPages.mm").read_text()
        self.assertIn("YTKACEMakeAppearanceOptionsController", pages_h)
        self.assertIn("YTKACEMakeDisplayRateOptionsController", pages_h)
        self.assertIn("YTKACEMakeAppearanceOptionsController", pages_mm)
        self.assertIn("YTKACEMakeDisplayRateOptionsController", pages_mm)
        self.assertIn("YTKACEAppearanceOptionsDefinition()", pages_mm)
        self.assertIn("YTKACEDisplayRateOptionsDefinition()", pages_mm)

    def test_stream_resolver_av1_vp9_h264_support(self):
        resolver_h = (ROOT / "Tweak" / "Features/Downloads/StreamResolver.h").read_text()
        resolver_mm = (ROOT / "Tweak" / "Features/Downloads/StreamResolver.mm").read_text()
        self.assertIn("isAV1", resolver_h)
        self.assertIn("isVP9", resolver_h)
        self.assertIn("isH264", resolver_h)
        self.assertIn("codecLabel", resolver_h)
        self.assertIn("av01", resolver_mm)
        self.assertIn("YTKACEPreferredCodecKey", resolver_mm)

if __name__ == "__main__":
    unittest.main()
