// Private preview defaults: links stay on the current host. No persistent state.
for (const link of document.querySelectorAll('[data-service]')) {
  const target = new URL(link.getAttribute('href'), location.href);
  target.hostname = location.hostname;
  target.protocol = location.protocol;
  target.port = { homepage: '8187', wiki: '8188', app: '8185' }[link.dataset.service];
  link.href = target.href;
}
for (const link of document.querySelectorAll('[hreflang]')) {
  link.hash = location.hash;
  link.addEventListener('click', () => { link.hash = location.hash; });
}
const menu = document.querySelector('#menu-toggle');
if (menu) menu.addEventListener('click', () => {
  const open = menu.getAttribute('aria-expanded') !== 'true';
  menu.setAttribute('aria-expanded', String(open));
  document.querySelector('#chapters').classList.toggle('expanded', open);
});
const search = document.querySelector('#search');
if (search) {
  let entries;
  const results = document.querySelector('#search-results');
  search.addEventListener('input', async () => {
    const query = search.value.trim().toLocaleLowerCase();
    results.replaceChildren();
    if (query.length < 2) return;
    try {
      entries ??= await fetch(search.dataset.index).then(response => {
        if (!response.ok) throw new Error('index');
        return response.json();
      });
      // Discard responses to earlier input.
      if (query !== search.value.trim().toLocaleLowerCase()) return;
      const matches = entries.filter(item => `${item.title} ${item.text}`.toLocaleLowerCase().includes(query));
      const message = document.createElement('p');
      message.textContent = `${matches.length} ${search.dataset.results}`;
      results.append(message);
      for (const item of matches) {
        const a = document.createElement('a');
        a.href = item.url; a.textContent = item.title;
        results.append(a);
      }
    } catch (_) { results.textContent = search.dataset.error; }
  });
}
