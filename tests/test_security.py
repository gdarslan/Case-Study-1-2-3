"""Local, dependency-free regression checks; no AWS calls."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


soar = load("soar_security", "case-study-02/soar/security.py")
rules = load("soar_rules", "case-study-02/soar/rule_engine.py")
hr = load("hr_auth", "case-study-03/app/backend/auth.py")
ADMIN = "A" * 32
VIEWER = "B" * 32


class SoarTests(unittest.TestCase):
    def test_bearer_auth(self):
        self.assertTrue(soar.authorized("Bearer " + ADMIN, ADMIN))
        self.assertFalse(soar.authorized("Bearer " + VIEWER, ADMIN))
        self.assertFalse(soar.authorized("", ADMIN))
        self.assertFalse(soar.authorized("Bearer short", "short"))

    def test_routes_high_and_critical_to_both_actions(self):
        for severity in ["HIGH", "critical", " Critical "]:
            self.assertEqual(rules.evaluate(soar.normalize_alert({"severity": severity})), ["SES", "S3"])

    def test_other_severities_archive_only(self):
        for payload in [{}, {"severity": "LOW"}, {"severity": ""}]:
            self.assertEqual(rules.evaluate(soar.normalize_alert(payload)), ["S3"])

    def test_reject_invalid_alerts(self):
        for payload in [[], None, {"severity": None}, {"severity": 42}, {"message": ["bad"]}, {"message": "x"*4097}]:
            with self.subTest(payload_type=type(payload).__name__), self.assertRaises(ValueError):
                soar.normalize_alert(payload)
        with self.assertRaises(ValueError):
            rules.evaluate({"severity": None})


class HrTests(unittest.TestCase):
    def test_distinct_tokens_resolve_roles(self):
        self.assertEqual(hr.authenticate("Bearer " + ADMIN, ADMIN, VIEWER), "admin")
        self.assertEqual(hr.authenticate("Bearer " + VIEWER, ADMIN, VIEWER), "viewer")

    def test_fail_closed(self):
        for header, admin, viewer in [(None, ADMIN, VIEWER), ("Bearer wrong", ADMIN, VIEWER),
                                       ("Bearer " + ADMIN, ADMIN, ADMIN), ("Bearer " + ADMIN, ADMIN, ""),
                                       ("Basic " + ADMIN, ADMIN, VIEWER)]:
            self.assertIsNone(hr.authenticate(header, admin, viewer))

    def test_frontend_does_not_render_employee_html(self):
        html = (ROOT / "case-study-03/app/frontend/index.html").read_text()
        self.assertNotIn("innerHTML", html)
        self.assertIn("td.textContent", html)


if __name__ == "__main__":
    unittest.main()
