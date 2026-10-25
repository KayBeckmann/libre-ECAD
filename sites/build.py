#!/usr/bin/env python3
"""Dependency-free, escaped static publishing with paired, versioned translations."""
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
LANGUAGES = ('de', 'en')
PORTS = {'homepage': 8187, 'wiki': 8188, 'app': 8185}


def esc(value):
    return html.escape(str(value), quote=True)


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def service_link(service, path, label, css=''):
    origin = os.environ.get(service.upper() + '_ORIGIN', '')
    if origin:
        url = urlsplit(origin)
        if url.scheme not in ('http', 'https') or not url.netloc or url.username or url.password or url.query or url.fragment or url.path not in ('', '/'):
            raise ValueError(f'{service}: expected an HTTP(S) origin without credentials or path')
    href = (origin.rstrip('/') or f'http://localhost:{PORTS[service]}') + path
    dynamic = f' data-service="{service}"' if not origin else ''
    return f'<a href="{esc(href)}"{dynamic} class="{esc(css)}">{esc(label)}</a>'


def wiki_path(lang, version, slug='start'):
    return f'/{lang}/{version}/{slug}/'


def checked_artifact(directory):
    manifest = directory / 'linux.json'
    if not manifest.exists():
        return None
    info = read_json(manifest)
    filename = info['file']
    if not re.fullmatch(r'libre-ecad-linux-x64-[a-f0-9]{7,40}\.tar\.gz', filename):
        raise ValueError('Invalid artifact filename')
    if not re.fullmatch(r'[a-f0-9]{40}', info['source']):
        raise ValueError('Artifact source must be a full commit')
    required = {'flutter-analyze', 'flutter-test', 'linux-release-build', 'linux-native-integration', 'linux-release-launch'}
    if set(info.get('checks', [])) != required:
        raise ValueError('Required artifact checks missing')
    for name, expected in [(filename, info['sha256']), ('verification.txt', info['log_sha256'])]:
        data = (directory / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f'Checksum mismatch: {name}')
        if name == filename and len(data) != info['bytes']:
            raise ValueError('Artifact size mismatch')
    return info


def validate(home, chapters):
    if set(home) != set(LANGUAGES) or home['de'].keys() != home['en'].keys():
        raise ValueError('Homepage translations must have matching fields')
    for field in ('features', 'models', 'platforms', 'legal_sections', 'nav', 'rail'):
        if len(home['de'][field]) != len(home['en'][field]):
            raise ValueError(f'Unpaired homepage field: {field}')
    slugs = set()
    for chapter in chapters:
        if not re.fullmatch(r'[a-z][a-z0-9-]*', chapter['slug']) or chapter['slug'] in slugs:
            raise ValueError('Invalid or duplicate chapter slug')
        slugs.add(chapter['slug'])
        if set(chapter['translations']) != set(LANGUAGES):
            raise ValueError('Missing chapter translation')
        sections = []
        for lang in LANGUAGES:
            translation = chapter['translations'][lang]
            ids = [section['id'] for section in translation['sections']]
            if len(set(ids)) != len(ids) or any(not re.fullmatch(r'[a-z][a-z0-9-]*', x) for x in ids):
                raise ValueError('Invalid or duplicate section ID')
            sections.append(ids)
            for section in translation['sections']:
                for block in section['blocks']:
                    if block['type'] not in ('p', 'note', 'ul', 'ol', 'code', 'link'):
                        raise ValueError('Unknown content block')
        if sections[0] != sections[1]:
            raise ValueError('Translations must preserve section IDs')
    for chapter in chapters:
        for translation in chapter['translations'].values():
            for section in translation['sections']:
                for block in section['blocks']:
                    if block['type'] == 'link' and block['chapter'] not in slugs:
                        raise ValueError('Broken chapter reference')


def shell(lang, title, description, body, other_path, home, version, site='homepage'):
    t = home[lang]
    other = 'en' if lang == 'de' else 'de'
    home_link = service_link('homepage', f'/{lang}/', 'LibreECAD', 'brand') if site == 'wiki' else f'<a class="brand" href="/{lang}/">Libre<span>ECAD</span></a>'
    navigation = service_link('wiki', wiki_path(lang, version), t['wiki']) if site == 'homepage' else service_link('homepage', f'/{lang}/', 'Homepage')
    navigation += service_link('app', '/', t['app'])
    navigation += f'<a class="language" href="{esc(other_path)}" hreflang="{other}" lang="{other}" aria-label="{"English" if other == "en" else "Deutsch"}">{other.upper()}</a>'
    return f'''<!doctype html>
<html lang="{lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>{esc(title)} · LibreECAD</title><meta name="description" content="{esc(description)}"><link rel="stylesheet" href="/assets/site.css"><script src="/assets/site.js" defer></script></head>
<body><a class="skip" href="#content">{esc(t['skip'])}</a><div class="wrap"><header class="topbar">{home_link}<nav aria-label="{"Hauptnavigation" if lang == "de" else "Main navigation"}">{navigation}</nav></header><p class="preview">{esc(t['preview'])}</p>{body}<footer class="footer"><span>LibreECAD · {esc(version)} · DE / EN</span><nav>{service_link('homepage', f'/{lang}/status/', t['legal'])}<a href="/assets/LICENSE.txt">{esc(t['license'])}</a><a href="/assets/LICENSE-Noto.txt">{esc(t['font_license'])}</a><a href="https://github.com/KayBeckmann/libre-ECAD">{esc(t['repository'])}</a></nav></footer></div></body></html>'''


def homepage(lang, home, version, artifact):
    t = home[lang]
    nav = '<nav class="rail">' + ''.join(f'<a href="#{id}">{esc(label)}</a>' for id, label in zip(('features', 'hosting', 'downloads'), t['nav'])) + '</nav>'
    drawing = f'<figure class="drawing"><div class="drawing-head"><span>{esc(t["drawing_title"])}</span><span>01 / 02</span></div><img src="/assets/drawing.svg" width="1200" height="800" alt="{esc(t["drawing_caption"])}"><figcaption>{esc(t["drawing_caption"])}</figcaption></figure>'
    body = '<main id="content">' + nav + f'<div class="hero"><div><p class="eyebrow">{esc(t["eyebrow"])}</p><h1>{esc(t["title"])}</h1><p class="lead">{esc(t["description"])}</p><div class="actions">' + service_link('app', '/', t['app'], 'button primary') + service_link('wiki', wiki_path(lang, version), t['wiki'], 'button') + '</div></div>' + drawing + '</div>'
    body += '<div class="rail">' + ''.join(f'<span>{esc(item)}</span>' for item in t['rail']) + '</div>'
    body += f'<section id="features"><div class="section-head"><h2>{esc(t["features_title"])}</h2><p class="muted">{esc(t["features_intro"])}</p></div><div class="features">'
    for index, (title, text) in enumerate(t['features'], 1):
        body += f'<div class="feature"><span class="number">/ 0{index}</span><h3>{esc(title)}</h3><p>{esc(text)}</p></div>'
    body += f'</div></section><section id="hosting"><div class="section-head"><h2>{esc(t["models_title"])}</h2><p class="muted">{esc(t["models_intro"])}</p></div><div class="models">'
    for tag, title, text, slug in t['models']:
        body += f'<div class="model"><span class="tag">{esc(tag)}</span><h3>{esc(title)}</h3><p>{esc(text)}</p>' + service_link('wiki', wiki_path(lang, version, slug), t['read_more']) + '</div>'
    body += f'</div></section><section id="downloads"><div class="section-head"><h2>{esc(t["downloads_title"])}</h2><p class="muted">{esc(t["downloads_intro"])}</p></div><div class="download-grid"><div class="download-box"><h3>{esc(t["linux"])}</h3>'
    if artifact:
        a = artifact
        body += f'<a class="button primary" href="/downloads/{esc(a["file"])}" download>{esc(t["download"])}</a><p class="doc-meta">{esc(t["size"])}: {a["bytes"] / 1048576:.1f} MiB · {esc(a["date"])}</p><p>{esc(t["source"])}<code>{esc(a["source"])}</code></p><p>{esc(t["checksum"])}<code>{esc(a["sha256"])}</code></p><p><a href="/downloads/verification.txt">{esc(t["evidence"])}</a> · <a href="/downloads/linux.json">Manifest</a> · <a href="/downloads/SHA256SUMS">SHA256SUMS</a></p>'
    else:
        body += f'<p>{esc(t["unavailable"])}</p>'
    body += f'<p class="muted">{esc(t["linux_note"])}</p></div><div>'
    for title, text in t['platforms']:
        body += f'<div class="platform"><strong>{esc(title)}</strong><span class="muted">{esc(text)}</span></div>'
    body += f'</div></div></section><section><p class="notice">{esc(t["limits"])}</p></section></main>'
    return shell(lang, t['title'], t['description'], body, f'/{"en" if lang == "de" else "de"}/', home, version)


def render_block(block, lang, version):
    kind = block['type']
    if kind in ('p', 'note'):
        return f'<p{" class=" + chr(34) + "notice" + chr(34) if kind == "note" else ""}>{esc(block["text"])}</p>'
    if kind in ('ul', 'ol'):
        return f'<{kind}>' + ''.join(f'<li>{esc(item)}</li>' for item in block['items']) + f'</{kind}>'
    if kind == 'code':
        return f'<pre><code>{esc(block["text"])}</code></pre>'
    return f'<p><a href="{wiki_path(lang, version, block["chapter"])}">{esc(block["text"])}</a></p>'


def wiki_page(lang, chapter, chapters, home, metadata):
    version = metadata['version']
    t = chapter['translations'][lang]
    de = lang == 'de'
    sidebar = f'<aside class="sidebar"><label for="search">{"Wiki durchsuchen" if de else "Search the wiki"}</label><input id="search" type="search" autocomplete="off" data-index="/{lang}/{version}/search.json" data-results="{"Treffer" if de else "results"}" data-error="{"Suchindex nicht erreichbar" if de else "Search index unavailable"}"><div id="search-results" aria-live="polite"></div><button id="menu-toggle" aria-expanded="false" aria-controls="chapters">{"Kapitel anzeigen" if de else "Show chapters"} ☰</button><nav id="chapters" class="chapters" aria-label="{"Kapitel" if de else "Chapters"}">'
    for c in chapters:
        current = ' aria-current="page"' if c['slug'] == chapter['slug'] else ''
        sidebar += f'<a href="{wiki_path(lang, version, c["slug"])}"{current}>{esc(c["translations"][lang]["title"])}</a>'
    sidebar += '</nav></aside>'
    article = f'<main id="content" class="article"><p class="eyebrow">WIKI / {esc(version)}</p><h1>{esc(t["title"])}</h1><p class="lead">{esc(t["intro"])}</p><div class="doc-meta">{metadata["date"]} · {"App-Quellstand" if de else "App source"} {esc(metadata["app_source"])} · {"Pflege" if de else "Maintainer"}: {esc(metadata["translation_owner"])}</div>'
    for section in t['sections']:
        article += f'<section id="{section["id"]}"><h2>{esc(section["title"])}</h2>' + ''.join(render_block(b, lang, version) for b in section['blocks']) + '</section>'
    index = chapters.index(chapter)
    article += '<nav class="pager">'
    for next_index, arrow in ((index - 1, '←'), (index + 1, '→')):
        if 0 <= next_index < len(chapters):
            c = chapters[next_index]
            article += f'<a href="{wiki_path(lang, version, c["slug"])}">{arrow} {esc(c["translations"][lang]["title"])}</a>'
    article += '</nav></main>'
    body = f'<div class="wiki-grid">{sidebar}{article}</div>'
    other = 'en' if de else 'de'
    return shell(lang, t['title'], t['intro'], body, wiki_path(other, version, chapter['slug']), home, version, 'wiki')


def write(root, relative, content):
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding='utf-8')


def build(output, artifact_dir=None):
    home = read_json(ROOT / 'content/home.json')
    metadata = read_json(ROOT / 'version.json')
    version = metadata['version']
    if not re.fullmatch(r'[a-z0-9-]+', version):
        raise ValueError('Invalid version')
    chapters = read_json(ROOT / 'content/wiki.json') if (ROOT / 'content/wiki.json').exists() else []
    validate(home, chapters)
    artifact_dir = artifact_dir or ROOT / 'artifacts'
    artifact = checked_artifact(artifact_dir)
    if artifact and not artifact['source'].startswith(metadata['app_source']):
        raise ValueError('Artifact and documentation reference different app versions')
    for site in ('homepage', 'wiki'):
        dest = output / site
        dest.mkdir(parents=True, exist_ok=True)
        # Regenerate into a clean site tree: removed artifacts must not stay reachable.
        for entry in dest.iterdir():
            shutil.rmtree(entry) if entry.is_dir() else entry.unlink()
        shutil.copytree(ROOT / 'assets', dest / 'assets')
        for name in ('NotoSans-Regular.ttf', 'NotoSans-Bold.ttf', 'LICENSE-Noto.txt'):
            shutil.copyfile(REPO / 'frontend/libre_ecad_app/assets/fonts' / name, dest / 'assets' / name)
        shutil.copyfile(REPO / 'LICENSE', dest / 'assets/LICENSE.txt')
        write(dest, 'health.txt', f'{site} {version}\n')
        write(dest, 'robots.txt', 'User-agent: *\nDisallow: /\n')
        write(dest, 'version.json', json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
        # A real language selector instead of an automatic redirect or saved preference.
        links = ''.join(f'<p><a class="button" href="{wiki_path(lang, version) if site == "wiki" else "/" + lang + "/"}" lang="{lang}">{"Deutsch" if lang == "de" else "English"}</a></p>' for lang in LANGUAGES)
        write(dest, 'index.html', shell('de', 'Deutsch / English', 'LibreECAD language selection', f'<main class="legal" id="content"><h1>LibreECAD</h1>{links}</main>', '/en/' if site == 'homepage' else wiki_path('en', version), home, version, site))
    for lang in LANGUAGES:
        write(output / 'homepage', f'{lang}/index.html', homepage(lang, home, version, artifact))
        t = home[lang]
        body = f'<main class="legal" id="content"><h1>{esc(t["legal_title"])}</h1>' + ''.join(f'<h2>{esc(title)}</h2><p>{esc(text)}</p>' for title, text in t['legal_sections']) + '</main>'
        write(output / 'homepage', f'{lang}/status/index.html', shell(lang, t['legal'], t['legal_title'], body, f'/{"en" if lang == "de" else "de"}/status/', home, version))
        search = []
        for chapter in chapters:
            path = wiki_path(lang, version, chapter['slug'])
            write(output / 'wiki', path.lstrip('/') + 'index.html', wiki_page(lang, chapter, chapters, home, metadata))
            t = chapter['translations'][lang]
            search.append({'title': t['title'], 'url': path, 'text': t['intro'] + ' ' + ' '.join(s['title'] + ' ' + ' '.join(b.get('text', ' '.join(b.get('items', []))) for b in s['blocks']) for s in t['sections'])})
        write(output / 'wiki', f'{lang}/{version}/search.json', json.dumps(search, ensure_ascii=False))
    if artifact:
        downloads = output / 'homepage/downloads'
        downloads.mkdir()
        for name in (artifact['file'], 'linux.json', 'verification.txt'):
            shutil.copyfile(artifact_dir / name, downloads / name)
        write(downloads, 'SHA256SUMS', f'{artifact["sha256"]}  {artifact["file"]}\n')
    return metadata


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build')
    args = parser.parse_args()
    metadata = build(args.output.resolve())
    print(f'Built homepage + wiki: {metadata["version"]} (de/en) → {args.output}')
