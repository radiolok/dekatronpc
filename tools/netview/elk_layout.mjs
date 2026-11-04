// ELK layout for netview.py: an ELK graph JSON on stdin, the laid-out graph on stdout.
import ELK from 'elkjs/lib/elk.bundled.js';

let src = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { src += c; });
process.stdin.on('end', async () => {
  try {
    const out = await new ELK().layout(JSON.parse(src));
    process.stdout.write(JSON.stringify(out));
  } catch (e) {
    process.stderr.write(String(e && e.stack || e) + '\n');
    process.exit(1);
  }
});
