import hashlib
from html.parser import HTMLParser
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import urlsplit, unquote

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('publisher', ROOT / 'build.py')
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class Links(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.links, self.ids = [], set()
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if 'id' in values:
            if values['id'] in self.ids:
                raise AssertionError('duplicate HTML id')
            self.ids.add(values['id'])
        for name in ('href', 'src'):
            if name in values:
                self.links.append(values[name])


class PublishingTests(unittest.TestCase):
    def setUp(self):
        self.home = publisher.read_json(ROOT / 'content/home.json')
        self.chapters = publisher.read_json(ROOT / 'content/wiki.json')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name) / 'site'
        self.artifacts = Path(self.temp.name) / 'artifacts'
        self.artifacts.mkdir()

    def artifact(self):
        data = b'synthetic-test-artifact'
        filename = 'libre-ecad-linux-x64-37603fa.tar.gz'
        (self.artifacts / filename).write_bytes(data)
        (self.artifacts / 'verification.txt').write_text('test-only evidence')
        info = {'file': filename, 'source': '37603fa' + '0' * 33, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'date': '2026-10-25', 'checks': ['flutter-analyze', 'flutter-test', 'linux-release-build', 'linux-native-integration', 'linux-release-launch'], 'log_sha256': hashlib.sha256(b'test-only evidence').hexdigest()}
        (self.artifacts / 'linux.json').write_text(json.dumps(info))
        return info

    def test_all_links_and_anchors_resolve_in_both_sites_and_languages(self):
        publisher.build(self.output, self.artifacts)
        count = 0
        for site in ('homepage', 'wiki'):
            for path in (self.output / site).rglob('*.html'):
                parsed = Links(path.read_text())
                for link in parsed.links:
                    url = urlsplit(link)
                    target_site = site
                    if url.netloc:
                        if url.hostname != 'localhost' or url.port == 8185:
                            continue
                        target_site = {8187: 'homepage', 8188: 'wiki'}[url.port]
                    target = self.output / target_site / unquote(url.path).lstrip('/') if url.path else path
                    if target.is_dir():
                        target /= 'index.html'
                    self.assertTrue(target.is_file(), f'{path}: {link}')
                    if url.fragment:
                        self.assertIn(unquote(url.fragment), Links(target.read_text()).ids, f'{path}: {link}')
                    count += 1
        self.assertGreater(count, 500)
        self.assertEqual(len(list((self.output / 'wiki').rglob('index.html'))), 23)

    def test_no_unverified_download_or_stale_artifact(self):
        self.artifact()
        publisher.build(self.output, self.artifacts)
        self.assertTrue((self.output / 'homepage/downloads/linux.json').exists())
        (self.artifacts / 'linux.json').unlink()
        publisher.build(self.output, self.artifacts)
        self.assertFalse((self.output / 'homepage/downloads').exists())
        for lang in ('de', 'en'):
            self.assertNotIn('href="/downloads/', (self.output / f'homepage/{lang}/index.html').read_text())

    def test_checksum_tamper_rejected(self):
        info = self.artifact()
        (self.artifacts / info['file']).write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'Checksum'):
            publisher.build(self.output, self.artifacts)

    def test_verification_log_tamper_rejected(self):
        self.artifact()
        (self.artifacts / 'verification.txt').write_text('modified')
        with self.assertRaisesRegex(ValueError, 'Checksum'):
            publisher.checked_artifact(self.artifacts)

    def test_missing_check_rejected(self):
        info = self.artifact()
        info['checks'].pop()
        (self.artifacts / 'linux.json').write_text(json.dumps(info))
        with self.assertRaisesRegex(ValueError, 'checks missing'):
            publisher.checked_artifact(self.artifacts)

    def test_mismatched_app_version_rejected(self):
        info = self.artifact()
        info['source'] = '1' * 40
        (self.artifacts / 'linux.json').write_text(json.dumps(info))
        with self.assertRaisesRegex(ValueError, 'different app versions'):
            publisher.build(self.output, self.artifacts)

    def test_artifact_traversal_rejected(self):
        info = self.artifact()
        info['file'] = '../outside.tar.gz'
        (self.artifacts / 'linux.json').write_text(json.dumps(info))
        with self.assertRaisesRegex(ValueError, 'filename'):
            publisher.checked_artifact(self.artifacts)

    def test_missing_translation_rejected(self):
        del self.chapters[0]['translations']['en']
        with self.assertRaisesRegex(ValueError, 'translation'):
            publisher.validate(self.home, self.chapters)

    def test_unpaired_anchor_rejected(self):
        self.chapters[0]['translations']['en']['sections'][0]['id'] = 'different'
        with self.assertRaisesRegex(ValueError, 'section IDs'):
            publisher.validate(self.home, self.chapters)

    def test_broken_chapter_link_rejected(self):
        self.chapters[0]['translations']['de']['sections'][0]['blocks'].append({'type': 'link', 'chapter': 'missing', 'text': 'broken'})
        with self.assertRaisesRegex(ValueError, 'reference'):
            publisher.validate(self.home, self.chapters)

    def test_content_escaped(self):
        html = publisher.render_block({'type': 'p', 'text': '<script>alert("x")</script>'}, 'de', 'm8-dev')
        self.assertNotIn('<script>', html)
        self.assertIn('&lt;script&gt;', html)
        result = publisher.render_block({'type': 'code', 'text': '<token> && command'}, 'en', 'm8-dev')
        self.assertIn('&lt;token&gt; &amp;&amp;', result)

    def test_configured_origins_and_rejection_of_unsafe_urls(self):
        with patch.dict('os.environ', {'WIKI_ORIGIN': 'https://wiki.example.test'}):
            result = publisher.service_link('wiki', '/de/m8-dev/start/', 'Wiki')
            self.assertIn('https://wiki.example.test/de/m8-dev/start/', result)
            self.assertNotIn('data-service', result)
        for invalid in ('javascript:alert(1)', 'https://user:password@example.test', 'https://example.test/path', 'https://example.test/?secret=x'):
            with self.subTest(origin=invalid), patch.dict('os.environ', {'APP_ORIGIN': invalid}):
                with self.assertRaises(ValueError):
                    publisher.service_link('app', '/', 'App')

    def test_search_indexes_match_chapter_paths(self):
        publisher.build(self.output, self.artifacts)
        for lang in ('de', 'en'):
            index = publisher.read_json(self.output / f'wiki/{lang}/m8-dev/search.json')
            self.assertEqual(len(index), len(self.chapters))
            for item in index:
                self.assertTrue((self.output / 'wiki' / item['url'].lstrip('/') / 'index.html').is_file())
                self.assertTrue(item['text'])


if __name__ == '__main__':
    unittest.main()
