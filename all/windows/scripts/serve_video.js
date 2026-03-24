const http = require('http');
const fs = require('fs');

const FILE = process.argv[2];
const PORT = 8080;

if (!FILE) { console.error('Usage: node serve_video.js <file>'); process.exit(1); }

const stat = fs.statSync(FILE);
const total = stat.size;
const ext = FILE.toLowerCase().split('.').pop();
const mimeTypes = { mkv: 'video/x-matroska', mp4: 'video/mp4', avi: 'video/x-msvideo', mov: 'video/quicktime', wmv: 'video/x-ms-wmv', webm: 'video/webm', m4v: 'video/mp4', ts: 'video/mp2t' };
const mime = mimeTypes[ext] || 'video/mp4';

const server = http.createServer((req, res) => {
  if (req.method === 'HEAD') {
    res.writeHead(200, {
      'Content-Type': mime,
      'Content-Length': total,
      'Accept-Ranges': 'bytes',
      'transferMode.dlna.org': 'Streaming'
    });
    return res.end();
  }

  if (req.headers.range) {
    const parts = req.headers.range.replace(/bytes=/, '').split('-');
    const start = parseInt(parts[0], 10);
    const end = parts[1] ? parseInt(parts[1], 10) : total - 1;
    res.writeHead(206, {
      'Content-Range': `bytes ${start}-${end}/${total}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': end - start + 1,
      'Content-Type': mime,
      'transferMode.dlna.org': 'Streaming'
    });
    fs.createReadStream(FILE, { start, end }).pipe(res);
  } else {
    res.writeHead(200, {
      'Content-Length': total,
      'Content-Type': mime,
      'Accept-Ranges': 'bytes',
      'transferMode.dlna.org': 'Streaming'
    });
    fs.createReadStream(FILE).pipe(res);
  }
});

server.listen(PORT, '0.0.0.0', () => console.log('READY'));
