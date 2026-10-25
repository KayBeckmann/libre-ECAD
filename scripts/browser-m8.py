#!/usr/bin/env python3
"""M8 acceptance against deployed independent private static sites."""
import argparse
import hashlib
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from urllib.request import urlopen
from playwright.sync_api import sync_playwright, expect


class PageLinks(HTMLParser):
    def __init__(self, body):
        super().__init__()
        self.links, self.ids = [], set()
        self.feed(body)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.add(attrs['id'])
        for name in ('href', 'src'):
            if name in attrs:
                self.links.append(attrs[name])


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('--homepage', default='http://127.0.0.1:8187')
    args.add_argument('--wiki', default='http://127.0.0.1:8188')
    args.add_argument('--screenshots', type=Path, default=Path('/tmp/libre-m8-browser'))
    args = args.parse_args()
    args.screenshots.mkdir(parents=True, exist_ok=True)
    origins = {args.homepage, args.wiki}
    todo = [origin + '/' for origin in origins]
    visited, anchors = {}, []
    while todo:
        url = todo.pop()
        if url in visited:
            continue
        with urlopen(url, timeout=20) as response:
            assert response.status == 200, url
            assert response.headers.get('Content-Security-Policy'), url
            assert response.headers.get('X-Content-Type-Options') == 'nosniff', url
            assert 'noindex' in response.headers.get('X-Robots-Tag', ''), url
            body = response.read()
            content_type = response.headers.get('Content-Type', '')
        parser = PageLinks(body.decode()) if 'text/html' in content_type else None
        visited[url] = parser
        if parser:
            for link in parser.links:
                resolved = urlsplit(urljoin(url, link))
                origin = f'{resolved.scheme}://{resolved.netloc}'
                if origin not in origins:
                    continue
                dest = origin + resolved.path
                if resolved.fragment:
                    anchors.append((dest, resolved.fragment))
                todo.append(dest)
    for url, anchor in anchors:
        assert anchor in visited[url].ids, (url, anchor)
    assert sum(page is not None for page in visited.values()) == 28
    print(f'HTTP crawl: {len(visited)} resources, {len(anchors)} anchors; headers present')

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(viewport={'width': 1440, 'height': 1000}, accept_downloads=True)
        page = context.new_page()
        errors, external = [], []
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.on('console', lambda msg: errors.append(msg.text) if msg.type == 'error' else None)
        page.on('request', lambda request: external.append(request.url) if f'{urlsplit(request.url).scheme}://{urlsplit(request.url).netloc}' not in origins else None)
        for lang in ('de', 'en'):
            page.goto(f'{args.homepage}/{lang}/', wait_until='networkidle')
            expect(page.locator('html')).to_have_attribute('lang', lang)
            assert page.locator('.drawing img').evaluate('(img) => img.complete && img.naturalWidth > 0')
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
            page.screenshot(path=str(args.screenshots / f'home-{lang}-desktop.png'), full_page=True)
            with page.expect_download() as download:
                page.locator('a[download]').click()
            file = Path(download.value.path())
            manifest = context.request.get(args.homepage + '/downloads/linux.json').json()
            assert hashlib.sha256(file.read_bytes()).hexdigest() == manifest['sha256']
        page.goto(args.homepage + '/de/#downloads', wait_until='networkidle')
        page.locator('a[hreflang=en]').click()
        page.wait_for_load_state('networkidle')
        assert page.url == args.homepage + '/en/#downloads'
        page.goto(args.wiki + '/de/m8-dev/offline/#limits', wait_until='networkidle')
        page.locator('a[hreflang=en]').click()
        page.wait_for_load_state('networkidle')
        assert page.url == args.wiki + '/en/m8-dev/offline/#limits'
        expect(page.locator('h1')).to_have_text('Prepared offline work')
        # Hash changes after load must also be retained by the language switch.
        page.evaluate("location.hash = 'prepare'")
        page.locator('a[hreflang=de]').click()
        page.wait_for_load_state('networkidle')
        assert page.url.endswith('/de/m8-dev/offline/#prepare')
        for lang, term, title in [('de', 'Wiederherstellung', 'Backup & Wiederherstellung'), ('en', 'recovery', 'Backup & recovery')]:
            page.goto(f'{args.wiki}/{lang}/m8-dev/start/', wait_until='networkidle')
            page.locator('#search').fill(term)
            expect(page.locator('#search-results').get_by_role('link', name=title, exact=True)).to_be_visible()
            page.locator('#search-results').get_by_role('link', name=title, exact=True).click()
            page.wait_for_load_state('networkidle')
            expect(page.locator('h1')).to_have_text(title)
            page.screenshot(path=str(args.screenshots / f'wiki-{lang}-desktop.png'), full_page=True)
            page.locator('#search').fill('zz-no-results-xx')
            expect(page.locator('#search-results p')).to_contain_text('0')
            page.locator('#search').fill('')
            expect(page.locator('#search-results')).to_be_empty()
        # Keyboard skip navigation.
        page.goto(args.homepage + '/de/', wait_until='networkidle')
        page.keyboard.press('Tab')
        expect(page.locator('.skip')).to_be_focused()
        page.keyboard.press('Enter')
        assert page.url.endswith('#content')
        # Every page at phone width, including long commands and checksums.
        page.set_viewport_size({'width': 390, 'height': 844})
        for url, parsed in visited.items():
            if parsed is None:
                continue
            page.goto(url, wait_until='networkidle')
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), url
        page.goto(args.wiki + '/de/m8-dev/start/', wait_until='networkidle')
        expect(page.locator('#chapters')).not_to_be_visible()
        page.locator('#menu-toggle').focus()
        page.keyboard.press('Enter')
        expect(page.locator('#menu-toggle')).to_have_attribute('aria-expanded', 'true')
        expect(page.locator('#chapters')).to_be_visible()
        page.locator('#chapters').get_by_role('link', name='Vorbereitete Offline-Arbeit').click()
        page.wait_for_load_state('networkidle')
        expect(page.locator('h1')).to_have_text('Vorbereitete Offline-Arbeit')
        page.screenshot(path=str(args.screenshots / 'wiki-mobile.png'), full_page=True)
        page.goto(args.homepage + '/de/', wait_until='networkidle')
        page.screenshot(path=str(args.screenshots / 'home-mobile.png'), full_page=True)
        assert not errors, errors
        assert not external, external
        assert not context.cookies()
        assert page.evaluate('localStorage.length + sessionStorage.length') == 0
        # Fixed origins support navigation and reading without JS as documented.
        nojs = browser.new_context(java_script_enabled=False)
        plain = nojs.new_page()
        plain.goto(args.homepage + '/de/')
        plain.locator('header').get_by_role('link', name='Dokumentation').click()
        expect(plain.locator('h1')).to_have_text('Start & Versionsstand')
        plain.locator('a[hreflang=en]').click()
        expect(plain.locator('h1')).to_have_text('Start & version')
        plain.set_viewport_size({'width': 390, 'height': 844})
        expect(plain.locator('#chapters')).to_be_visible()
        nojs.close()
        context.close()
        browser.close()
    print('PASS DE/EN, search, hash-preserving language switch, keyboard, mobile, no external requests/storage, no-JS links, actual download checksum')


if __name__ == '__main__':
    main()
