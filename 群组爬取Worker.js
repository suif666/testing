/**
 * 群组成员爬取 + 名单存储（Cloudflare Worker）
 * ============================================================
 * 一次性准备好：先在后台把群组名单爬全、存进 KV，之后脚本只读后台。
 *
 * 【需要绑定】
 *   KV 命名空间，变量名必须是 GROUPS
 *   （Settings → Variables and Secrets / Bindings → KV Namespace → 变量名填 GROUPS）
 *
 * 【接口】
 *   GET  /                                  状态页（浏览器直接打开看）
 *   GET  /test?groupId=7                    自检：这个 Worker 能不能访问 Roblox
 *   GET  /crawl?groupId=7&pages=20          爬一批（1 页 = 100 人），可反复调
 *   GET  /status?groupId=7                  进度（总人数 / 已爬 / 状态）
 *   GET  /users?groupId=7&offset=0&limit=500   取名单
 *   GET  /list                              已经爬过的群组列表
 *   GET  /export?groupId=7&format=csv       导出 CSV（浏览器直接下载）
 *   GET  /reset?groupId=7                   清掉这个群的数据（重新爬）
 *   POST /push                              JSON 推送：{groupId, name, memberCount, done, members:[[id,name,display,rank,role]]}
 *   GET  /pushget?groupId=7&done=0&data=... 同上，但用 GET（手机上只有 game:HttpGet 时的兜底）
 *                                           data 格式：id:名字:显示名:等级:角色|id:...
 *
 * 【定时任务（建议加）】
 *   Cron 触发器填：每 1 分钟一次（表达式是 星号 斜杠1 空格 星号 星号 星号 星号）
 *   加完之后，只要有人点过一次「开始爬取」，后台就会自己慢慢爬完，不用一直挂着
 *
 * 【可选保护】
 *   给 Worker 加一个环境变量 KEY=你的密码，之后所有接口都要带 &key=密码
 */

const RBX_UA =
	'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

const CHUNK = 1000;          // 每个 KV 分片存多少人
const DEFAULT_PAGES = 20;    // 每次 /crawl 默认爬几页（1 页 = 100 人）
const CRON_PAGES = 30;       // 定时任务每次爬几页
const PAGE_DELAY_MS = 200;   // 页间隔，防 Roblox 429
const MAX_RETURN = 1000;     // /users 单次最多返回多少条
const MAX_READ_CHUNKS = 60;  // /users 单次最多读几个分片

const CORS = {
	'Access-Control-Allow-Origin': '*',
	'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
	'Access-Control-Allow-Headers': 'Content-Type',
};

const json = (obj, status = 200) =>
	new Response(JSON.stringify(obj), {
		status,
		headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS },
	});

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const K = {
	meta: (id) => `g:${id}:meta`,
	chunk: (id, i) => `g:${id}:c:${i}`,
	index: 'groups:index',
};

const pub = (m) =>
	m && {
		groupId: m.groupId,
		name: m.name,
		memberCount: m.memberCount,
		scraped: (m.scraped || 0) + (m.buffer ? m.buffer.length : 0),
		stored: m.scraped || 0,
		buffered: m.buffer ? m.buffer.length : 0,
		chunks: m.chunks || 0,
		status: m.status,
		hasCursor: !!m.cursor,
		lastError: m.lastError || null,
		startedAt: m.startedAt || null,
		updatedAt: m.updatedAt || null,
	};

/** 请求 Roblox 公开接口 */
async function rbx(path) {
	try {
		const res = await fetch('https://' + path, {
			headers: {
				'User-Agent': RBX_UA,
				Accept: 'application/json',
				'Accept-Language': 'en-US,en;q=0.9',
			},
		});
		const text = await res.text();
		let body = null;
		try {
			body = JSON.parse(text);
		} catch (e) {
			body = null;
		}
		return { status: res.status, body, text };
	} catch (e) {
		return { status: 0, body: null, text: 'fetch failed: ' + String(e) };
	}
}

async function getMeta(env, id) {
	return (await env.GROUPS.get(K.meta(id), 'json')) || null;
}

async function saveMeta(env, m) {
	m.updatedAt = Date.now();
	await env.GROUPS.put(K.meta(m.groupId), JSON.stringify(m));
}

async function indexUpsert(env, m) {
	const list = (await env.GROUPS.get(K.index, 'json')) || [];
	const row = {
		groupId: m.groupId,
		name: m.name,
		memberCount: m.memberCount,
		scraped: (m.scraped || 0) + (m.buffer ? m.buffer.length : 0),
		status: m.status,
		updatedAt: Date.now(),
	};
	const i = list.findIndex((x) => x.groupId === m.groupId);
	if (i >= 0) list[i] = row;
	else list.push(row);
	await env.GROUPS.put(K.index, JSON.stringify(list.slice(-300)));
}

/** 把缓冲区里的成员落盘成分片 */
async function flush(env, m) {
	if (!m.buffer || m.buffer.length === 0) return;
	while (m.buffer.length > 0) {
		const part = m.buffer.splice(0, CHUNK);
		await env.GROUPS.put(K.chunk(m.groupId, m.chunks), JSON.stringify(part));
		m.chunks++;
		m.scraped = (m.scraped || 0) + part.length;
	}
	await saveMeta(env, m);
	await indexUpsert(env, m);
}

/** 爬一批 */
async function crawlBatch(env, groupId, maxPages) {
	groupId = String(groupId).replace(/[^0-9]/g, '');
	if (!groupId) return { ok: false, error: '群组 ID 不对' };

	let m = await getMeta(env, groupId);
	if (!m) {
		const info = await rbx(`groups.roblox.com/v1/groups/${groupId}`);
		if (info.status !== 200) {
			return {
				ok: false,
				step: 'group-info',
				rbxStatus: info.status,
				body: (info.text || '').slice(0, 200),
				hint:
					info.status === 403
						? '这个 Worker 的出口 IP 被 Roblox 拦了（Roblox.com is not available）→ 改用手机端爬取 + /push 上传'
						: info.status === 0
						? 'Worker 连不上 Roblox（网络问题）'
						: '群组不存在，或者这个群拿不到成员列表',
			};
		}
		m = {
			groupId: Number(groupId),
			name: info.body && info.body.name,
			memberCount: info.body && info.body.memberCount,
			scraped: 0,
			chunks: 0,
			buffer: [],
			cursor: '',
			status: 'running',
			startedAt: Date.now(),
			lastError: null,
		};
		await saveMeta(env, m);
		await indexUpsert(env, m);
	}

	if (m.status === 'done') return { ok: true, done: true, meta: pub(m) };

	let pages = 0;
	while (pages < maxPages) {
		const url =
			`groups.roblox.com/v1/groups/${groupId}/users?limit=100&sortOrder=Asc` +
			(m.cursor ? '&cursor=' + encodeURIComponent(m.cursor) : '');
		const r = await rbx(url);

		if (r.status === 429) {
			m.lastError = 'Roblox 429 限流，等一会儿再继续';
			await saveMeta(env, m);
			return { ok: false, rateLimited: true, meta: pub(m) };
		}
		if (r.status !== 200) {
			m.lastError = `Roblox ${r.status}: ${(r.text || '').slice(0, 150)}`;
			await saveMeta(env, m);
			return { ok: false, rbxStatus: r.status, meta: pub(m) };
		}

		const data = (r.body && r.body.data) || [];
		for (const u of data) {
			const user = u.user || {};
			m.buffer.push([
				user.userId,
				user.username || '',
				user.displayName || '',
				u.role ? u.role.rank : 0,
				u.role && u.role.name ? u.role.name : '',
			]);
		}
		m.cursor = (r.body && r.body.nextPageCursor) || '';
		pages++;

		if (m.buffer.length >= CHUNK) await flush(env, m);
		if (!m.cursor) {
			m.status = 'done';
			break;
		}
		await sleep(PAGE_DELAY_MS);
	}

	if (m.status === 'done' || m.buffer.length >= CHUNK) await flush(env, m);
	else await saveMeta(env, m);

	return { ok: true, done: m.status === 'done', pagesThisCall: pages, meta: pub(m) };
}

/** 读名单 */
async function readUsers(env, id, offset, limit) {
	const m = await getMeta(env, id);
	if (!m) return { ok: false, error: '这个群还没爬过，先调 /crawl 或 /push' };

	const out = [];
	let seen = 0;
	const chunks = Math.min(m.chunks || 0, MAX_READ_CHUNKS);
	for (let c = 0; c < chunks && out.length < limit; c++) {
		const chunk = (await env.GROUPS.get(K.chunk(id, c), 'json')) || [];
		for (const row of chunk) {
			if (seen < offset) {
				seen++;
				continue;
			}
			out.push(row);
			seen++;
			if (out.length >= limit) break;
		}
	}
	return {
		ok: true,
		groupId: Number(id),
		name: m.name,
		memberCount: m.memberCount,
		scrapedTotal: m.scraped || 0,
		chunks: m.chunks || 0,
		status: m.status,
		offset,
		returned: out.length,
		fields: ['userId', 'username', 'displayName', 'rank', 'role'],
		users: out,
	};
}

/** 清掉某个群的数据 */
async function resetGroup(env, id) {
	const m = await getMeta(env, id);
	if (!m) return { ok: false, error: '没有这个群的数据' };
	let deleted = 0;
	for (let c = 0; c < (m.chunks || 0); c++) {
		await env.GROUPS.delete(K.chunk(id, c));
		deleted++;
	}
	await env.GROUPS.delete(K.meta(id));
	const list = (await env.GROUPS.get(K.index, 'json')) || [];
	await env.GROUPS.put(K.index, JSON.stringify(list.filter((x) => String(x.groupId) !== String(id))));
	return { ok: true, deletedChunks: deleted };
}

/** 接收手机端推上来的一批 */
async function pushMembers(env, payload) {
	const id = String(payload.groupId || '').replace(/[^0-9]/g, '');
	if (!id) return { ok: false, error: '缺少 groupId' };

	let m = await getMeta(env, id);
	if (!m) {
		m = {
			groupId: Number(id),
			name: payload.name || null,
			memberCount: payload.memberCount || null,
			scraped: 0,
			chunks: 0,
			buffer: [],
			cursor: '',
			status: 'running',
			startedAt: Date.now(),
			lastError: null,
		};
	}
	if (payload.name) m.name = payload.name;
	if (payload.memberCount) m.memberCount = payload.memberCount;

	const members = payload.members || [];
	for (const row of members) {
		if (!row || !row.length) continue;
		m.buffer.push([row[0], row[1] || '', row[2] || '', row[3] || 0, row[4] || '']);
	}
	if (m.buffer.length >= CHUNK || payload.done) await flush(env, m);
	else await saveMeta(env, m);

	if (payload.done) {
		await flush(env, m);
		m.status = 'done';
		await saveMeta(env, m);
		await indexUpsert(env, m);
	}
	return { ok: true, added: members.length, meta: pub(m) };
}

/** CSV 导出 */
async function exportCsv(env, id) {
	const m = await getMeta(env, id);
	if (!m) return new Response('没有这个群的数据', { status: 404, headers: CORS });
	const lines = ['userId,username,displayName,rank,role'];
	const chunks = Math.min(m.chunks || 0, 500);
	for (let c = 0; c < chunks; c++) {
		const chunk = (await env.GROUPS.get(K.chunk(id, c), 'json')) || [];
		for (const r of chunk) {
			lines.push(
				[r[0], r[1], r[2], r[3], r[4]]
					.map((v) => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"')
					.join(',')
			);
		}
	}
	const csv = '\ufeff' + lines.join('\r\n');
	return new Response(csv, {
		headers: {
			'Content-Type': 'text/csv; charset=utf-8',
			'Content-Disposition': `attachment; filename="group_${id}_members.csv"`,
			...CORS,
		},
	});
}

/** 状态页 */
async function statusPage(env) {
	const list = (await env.GROUPS.get(K.index, 'json')) || [];
	const rows = list
		.map((x) => {
			const pct = x.memberCount ? Math.floor((x.scraped / x.memberCount) * 100) : 0;
			return `<tr><td>${x.groupId}</td><td>${x.name || ''}</td><td>${x.scraped}/${x.memberCount || '?'}</td><td>${pct}%</td><td>${x.status}</td></tr>`;
		})
		.join('');
	const html = `<!doctype html><meta charset="utf-8"><title>群组名单后台</title>
<style>body{font-family:-apple-system,sans-serif;background:#111;color:#eee;padding:20px}
table{border-collapse:collapse}td,th{border:1px solid #444;padding:6px 10px}
a{color:#6cf}code{background:#222;padding:2px 5px;border-radius:4px}</style>
<h2>群组名单后台</h2>
<p>已登记的群组：</p>
<table><tr><th>群组ID</th><th>名字</th><th>已爬/总人数</th><th>进度</th><th>状态</th></tr>${rows || '<tr><td colspan=5>还没有数据</td></tr>'}</table>
<h3>手动用法</h3>
<p>
自检：<a href="/test?groupId=7">/test?groupId=7</a><br>
爬一批：<a href="/crawl?groupId=7&pages=20">/crawl?groupId=7&pages=20</a><br>
看进度：<a href="/status?groupId=7">/status?groupId=7</a><br>
取名单：<a href="/users?groupId=7&offset=0&limit=200">/users?groupId=7&offset=0&limit=200</a><br>
导出CSV：<a href="/export?groupId=7">/export?groupId=7</a>
</p>`;
	return new Response(html, { headers: { 'Content-Type': 'text/html; charset=utf-8', ...CORS } });
}

/** 解析 GET 方式的 push（手机端兜底）*/
function parsePushGet(params) {
	const data = params.get('data') || '';
	const members = [];
	for (const item of data.split('|')) {
		if (!item) continue;
		const f = item.split(':');
		if (!f[0]) continue;
		members.push([Number(f[0]) || f[0], f[1] || '', f[2] || '', Number(f[3]) || 0, f[4] || '']);
	}
	return {
		groupId: params.get('groupId'),
		name: params.get('name') || null,
		memberCount: Number(params.get('memberCount')) || null,
		done: params.get('done') === '1',
		members,
	};
}

export default {
	async fetch(request, env) {
		const url = new URL(request.url);
		const p = url.searchParams;

		if (request.method === 'OPTIONS') return new Response(null, { headers: CORS });

		// 可选密码保护
		if (env.KEY && p.get('key') !== env.KEY) {
			return json({ ok: false, error: 'key 不对（后台设了 KEY 环境变量）' }, 401);
		}

		const path = url.pathname.replace(/\/+$/, '') || '/';

		try {
			if (path === '/') return await statusPage(env);

			if (path === '/list') {
				return json({ ok: true, groups: (await env.GROUPS.get(K.index, 'json')) || [] });
			}

			if (path === '/test') {
				const id = p.get('groupId') || '7';
				const r = await rbx(`groups.roblox.com/v1/groups/${id}`);
				return json({
					ok: r.status === 200,
					rbxStatus: r.status,
					groupName: r.body && r.body.name,
					memberCount: r.body && r.body.memberCount,
					body: (r.text || '').slice(0, 200),
					hint:
						r.status === 403
							? 'Cloudflare 出口 IP 被 Roblox 拦了 → 用手机端爬取 + /pushget 上传'
							: r.status === 200
							? '后台可以直连 Roblox，正常爬就完事'
							: '看上面 body 里的报错',
				});
			}

			if (path === '/crawl') {
				const id = p.get('groupId');
				if (!id) return json({ ok: false, error: '缺少 groupId' }, 400);
				const pages = Math.min(Number(p.get('pages')) || DEFAULT_PAGES, 40);
				return json(await crawlBatch(env, id, pages));
			}

			if (path === '/status') {
				const id = p.get('groupId');
				if (!id) return json({ ok: false, error: '缺少 groupId' }, 400);
				const m = await getMeta(env, id);
				if (!m) return json({ ok: false, error: '这个群还没爬过' }, 404);
				return json({ ok: true, meta: pub(m) });
			}

			if (path === '/users') {
				const id = p.get('groupId');
				if (!id) return json({ ok: false, error: '缺少 groupId' }, 400);
				const offset = Math.max(Number(p.get('offset')) || 0, 0);
				const limit = Math.min(Number(p.get('limit')) || 200, MAX_RETURN);
				return json(await readUsers(env, id, offset, limit));
			}

			if (path === '/export') {
				const id = p.get('groupId');
				if (!id) return json({ ok: false, error: '缺少 groupId' }, 400);
				return await exportCsv(env, id);
			}

			if (path === '/reset') {
				const id = p.get('groupId');
				if (!id) return json({ ok: false, error: '缺少 groupId' }, 400);
				return json(await resetGroup(env, id));
			}

			if (path === '/push') {
				if (request.method !== 'POST') return json({ ok: false, error: '用 POST' }, 405);
				const body = await request.json().catch(() => null);
				if (!body) return json({ ok: false, error: 'body 不是 JSON' }, 400);
				return json(await pushMembers(env, body));
			}

			if (path === '/pushget') {
				return json(await pushMembers(env, parsePushGet(p)));
			}

			return json({ ok: false, error: '没有这个接口', path }, 404);
		} catch (e) {
			return json({ ok: false, error: String(e) }, 500);
		}
	},

	/** 定时任务：把 running 的任务自己爬完（需要在 Cloudflare 加 Cron 触发器） */
	async scheduled(event, env, ctx) {
		ctx.waitUntil(
			(async () => {
				const list = (await env.GROUPS.get(K.index, 'json')) || [];
				const running = list.filter((x) => x.status === 'running').slice(0, 3);
				for (const x of running) {
					try {
						await crawlBatch(env, x.groupId, CRON_PAGES);
					} catch (e) {
						// 出错就跳过，下次再试
					}
				}
			})()
		);
	},
};
