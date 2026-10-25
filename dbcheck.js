const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('D:/Develop/wewe-rss/apps/server/data/wewe-rss.db', { readOnly: true });
const rows = db.prepare("SELECT id, name, status, substr(token,1,25) as tok, updated_at FROM accounts").all();
console.log(JSON.stringify(rows, null, 2));
const cnt = db.prepare("SELECT count(*) as n FROM articles").get();
console.log('ARTICLES:', cnt.n);
db.close();
